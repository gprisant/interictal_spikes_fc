clear
clc
close

% global variables and packages
addpath(genpath('/Users/stiso/Documents/Code/interictal_spikes_fc/'))
addpath(genpath('/Users/stiso/Documents/MATLAB/eeglab_current/'))
addpath('/Users/stiso/Documents/MATLAB/fieldtrip-20170830/')

release = '1';
protocol = 'r1';

top_dir = '/Volumes/bassett-data/Jeni/RAM/';
release_dir = [top_dir, 'release', release '/'];
eval(['cd ', top_dir])

detector = '';

min_chan = 3; % minimum number of channels that need to be recruited
win = 0.05; % size of the window to look for the minimum number of channels, in seconds
seq = 0.015; % 15ms for spikes within a sequence, taken from Erin Conrads Brain paper
thr = 0.002;
if strcmp(detector, '')
    discharge_tol=0.005; % taken from spike function
else
    spike_srate = 200;
end % taken from spike function
min_chan = 3;

%% Pick which subject

subj = 'R1045E';
exper = 'YC1';
sess = '1';

subj = 'R1031M';
exper = 'PAL2';
sess = '1';

subj = 'R1015J';
exper = 'FR1';
sess = '0';

subj = 'R1021D';
exper = 'YC1';
sess = '0';

subj = 'R1001P';
exper = 'FR2';
sess = '0';

subj = 'R1060M';
exper = 'FR2';
sess = '0';

%% Get spikes

%eval(['info = info.protocols.', protocol,';']);
out_clean = [];
marker = [];

if ~exist([top_dir, 'processed/release',release, '/', protocol, '/', subj, '/'], 'dir')
    mkdir([top_dir, 'processed/release',release, '/', protocol, '/', subj, '/']);
end

fprintf('******************************************\nStarting preprocessing for subject %s...\n', subj)



% get the path names for this session, loaded from a json file
%eval(['curr_info = info.subjects.' subj, '.experiments.' exper, '.sessions.x', sess, ';'])

% folders
raw_dir = [release_dir, 'protocols/', protocol, '/subjects/', subj, '/experiments/', exper, '/sessions/', sess, '/ephys/current_processed/'];
save_dir = [top_dir, 'processed/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
img_dir = [top_dir, 'img/diagnostics/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
if ~exist(img_dir, 'dir')
    mkdir(img_dir);
end
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

fprintf('\nExperiment %s session %s\n\n', exper, sess)

if exist([save_dir, 'data_clean.mat'], 'file')
    load([save_dir, 'data_clean.mat'])
    load([save_dir, 'header.mat'])
    load([save_dir, 'channel_info.mat'])
    
    % combine soz and interictal
    all_soz = unique([cell2mat(cellfun(@(x) find(strcmpi(x, ft_data.label)), soz, 'UniformOutput', false)); cell2mat(cellfun(@(x) find(strcmpi(x, ft_data.label)), interictal_cont, 'UniformOutput', false))]);
    nChan = numel(ft_data.label);
    
    if isempty(all_soz)
        warning('The interictal and SOZ channels were not marked for this subject')
    end
    
    nTrial = numel(ft_data.trial);
    if strcmp(detector,'')
        
        for j = 1:nTrial
            % initialize
            out_clean(j).pos = 0;
            out_clean(j).dur = 0;
            out_clean(j).chan = 0;
            out_clean(j).weight = 0;
            out_clean(j).con = 0;
            out_clean(j).seq = 0;
            % run detection alg
            [out,MARKER] = ...
                spike_detector_hilbert_v16_byISARG(ft_data.trial{j}', header.sample_rate);
            % sort spikes by onset
            [sort_pos,I] = sort(out.pos, 'ascend');
            out.pos = sort_pos;
            out.chan = out.chan(I);
            out.con = out.con(I);
            out.dur = out.dur(I);
            out.weight = out.weight(I);
            out.pdf = out.pdf(I);
            out.seq = nan(size(out.pos));
            seq_cnt = 0; % counter for sequences, you can reset it here because the same number will never be in the same 1s window later on
            
            % eliminate some spikes
            include_length = win;
            nSamp = size(MARKER.d,1);
            nSpike = numel(out.pos);
            kept_spike = false(size(out.pos));
            
            for i = 1:nSpike
                curr_pos = out.pos(i);
                
                if kept_spike(i) == 0
                    win_spike = (out.pos > curr_pos & out.pos < (curr_pos + win));
                    % add spikes within 15ms of the
                    % last one
                    last_spike = max(out.pos(win_spike));
                    curr_sum = 0;
                    while curr_sum < sum(win_spike) % stop when you stop adding new spikes
                        curr_sum = sum(win_spike);
                        win_spike = win_spike | (out.pos > last_spike & out.pos < (last_spike + seq));
                        last_spike = max(out.pos(win_spike));
                    end
                    win_chan = out.chan(win_spike);
                    
                    % set sequence ID for all spikes
                    % in this window
                    seqs = struct('idx',[],'chan',[]);
                    if sum(win_spike) > 0
                        [~,leader_idx] = min(out.pos(win_spike));
                        leader = win_chan(leader_idx);
                        if sum(win_chan == leader) == 1
                            out.seq(win_spike) = seq_cnt;
                            seqs(1).idx = find(win_spike);
                            seqs(1).chan = win_chan;
                            seq_cnt = seq_cnt + 1;
                        else
                            % parse sequence at the
                            % leader.
                            end_pts = find(win_chan == leader);
                            end_pts = [end_pts; numel(win_chan) + 1];
                            win_idx = find(win_spike);
                            for m = 1:(numel(end_pts)-1)
                                seqs(m).chan = win_chan(end_pts(m):(end_pts(m+1)-1));
                                seqs(m).idx = win_idx(end_pts(m):(end_pts(m+1)-1));
                                out.seq(seqs(m).idx) = seq_cnt;
                                seq_cnt = seq_cnt + 1;
                            end
                        end
                    end
                    % for each sequence, remove events that generalize
                    % to 80% of elecs within 2ms,
                    % keep if it spread to at least
                    % 3 channels
                    for m = 1:numel(seqs)
                        time_between = diff(out.pos(seqs(m).idx));
                        if (numel(unique(seqs(m).chan)) >= min_chan) && ~(numel(unique(seqs(m).chan(time_between <= thr))) >= nChan*.5)
                            kept_spike(seqs(m).idx) = true;
                        end
                    end
                end
            end
            % select only good spikes
            out_clean(j).pos = out.pos(kept_spike);
            out_clean(j).dur = out.dur(kept_spike);
            out_clean(j).chan = out.chan(kept_spike);
            out_clean(j).weight = out.weight(kept_spike);
            out_clean(j).con = out.con(kept_spike);
            out_clean(j).seq = out.seq(kept_spike);
            fprintf('This dataset had %d IEDs per second\n', numel(kept_spike)/(size(MARKER.M,1)/MARKER.fs))
            
            % get new M
            m_clean = zeros(size(MARKER.M));
            for i=1:size(out_clean(j).pos,1)
                m_clean(round(out_clean(j).pos(i)*MARKER.fs:out_clean(j).pos(i)*MARKER.fs+discharge_tol*MARKER.fs),...
                    out_clean(j).chan(i))=out_clean(j).con(i);
            end
            marker(j).m_clean = m_clean;
            marker(j).d = MARKER.d;
            marker(j).fs = MARKER.fs;
            
            
            
        end
        
    else
        for j = 1:nTrial
            curr = [];
            results = Delphos_detector(ft_data.trial{j},ft_data.label, 'SEEG', ft_data.fsample, {'Spk'}, [], [], 50,[]);
            curr.pos = [results.markers(:).position];
            curr.dur = [results.markers(:).duration];
            curr.value = [results.markers(:).value];
            % change channels to numbers
            channels = cellfun(@(x) find(strcmp(x,ft_data.label)), {results.markers.channels});
            curr.chan = channels;
            
            % remove spurious spikes
            % initialize
            out_clean(j).pos = 0;
            out_clean(j).dur = 0;
            out_clean(j).chan = 0;
            
            include_length = win;%.300*MARKER.fs;
            nSamp = size(ft_data.trial{j},2);
            nSpike = numel(curr.pos);
            kept_spike = false(size(curr.pos));
            
            for i = 1:nSpike
                curr_pos = curr.pos(i);
                
                %if ~kept_spike(i)
                win_spike = (curr.pos > curr_pos & curr.pos < (curr_pos + win));
                win_chan = curr.chan(win_spike);
                
                if numel(unique(win_chan)) >= min_chan
                    kept_spike(win_spike) = true;
                end
                
                %end
            end
            % select only good spikes
            out_clean(j).pos = curr.pos(kept_spike);
            out_clean(j).dur = curr.dur(kept_spike);
            out_clean(j).chan = curr.chan(kept_spike);
            fprintf('This dataset had %d IEDs per second\n', numel(kept_spike)/(size(ft_data.trial{j},2)/ft_data.fsample))
            
            
            % get new M
            m = zeros(nChan, ceil(size(ft_data.trial{j},2)/ft_data.fsample*spike_srate));
            for i=1:numel(out_clean(j).pos)
                m(out_clean(j).chan(i),round(out_clean(j).pos(i)*spike_srate))=1;
            end
            marker(j).m_clean = m;
            marker(j).fs = spike_srate;
            
        end
    end
end



%% Plot everything

eegplot(marker(1).d', 'srate', marker(1).fs)
eegplot(marker(1).M', 'srate', marker(1).fs)
eegplot(marker(1).m_clean', 'srate', marker(1).fs)

st = 24*marker(1).fs;
en = 44*marker(1).fs;
figure(1); clf
plot_lfp(marker(1).d(st:en,:)', 24*marker(1).fs); hold on
plot_lfp(marker(1).d(logical(marker(1).m_clean(st:en,:)))', 24*marker(1).fs, 'r*');



%% Plot spikes

nElec = size(ft_data.trial{1},1);

% plot length in samples
l = 4000;
nPlots = 10;

cmax = max(out_clean(1).seq);


for j = 1:nPlots
    % randomly pick a spike
    st = size(marker(1).d,1);
    while st > (size(marker(1).d,1) - l - 101) || st < 0
        curr = randi(numel(out_clean(1).pos));
        st = round(out_clean(1).pos(curr)*marker(1).fs) - 100;
    end
    
    % get data ready for plotting
    data = (marker(1).d - mean(marker(1).d))';
    
    % get offset for each channel
    maxes = zeros(size(data,1),1) + mean(max(data, [], 2));
    offset = zeros(size(maxes));
    for i = 1:numel(offset)
        offset(i) = sum(maxes(i:end));
    end
    % add to data
    data = data + offset;
    
    % get x_vector
    x = 1:l;
    x = x./marker(1).fs;
    
    % offset markers
    markers = marker(1).m_clean';
    for i = 1:nElec
        markers(i,markers(i,:) ~= 0) = markers(i,markers(i,:) ~= 0) + offset(i);
    end
    
    % plot
    figure(1); clf
    set(gcf, 'Position',  [100, 100, 800, 1200]);
    plot(x,data(:,st:(st + l - 1)), 'k', 'linewidth', 1.5); hold on
    xlabel('Time (s)')
    ylim([min(min(data(:,st:(st + l - 1)))), max(max(data(:,st:(st + l - 1))))])
    plot(x, markers(:,st:(st + l - 1)), 'rx', 'linewidth', 2)
    hold off
    saveas(gca, [top_dir, 'img/spike_examples/', subj, '_', num2str(curr), detector, '.png'], 'png')
    
end



