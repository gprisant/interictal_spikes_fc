%% Find Spikes
% automatically detects IEDs, using one of two spike detectors: janca et. al (http://github.com/hoameng/cognitive-spike-2016) or delphos (https://scanr.enseignementsup-recherche.gouv.fr/publication/hal-02139507)

clear
clc
close all
warning ON

addpath(genpath('/Users/stiso/Documents/Code/interictal_spikes_fc/'))
addpath('/Users/stiso/Documents/MATLAB/fieldtrip-20170830/')
addpath(genpath('/Users/stiso/Documents/MATLAB/BCT/'))

%% global variables

% global variables and packages
top_dir = '/Volumes/bassett-data/Jeni/RAM/';
eval(['cd ', top_dir])
releases = ['1', '2', '3'];

% which detector are you using? '' for Janca et al, '_delphos' for delphos
detector = '_param2';

% parameters for eliminated spikes
min_chan = 3; % minimum number of channels that need to be recruited
thr = 0.002; % reject spike if they spread to a lot of channels in less than 2ms (larger than paper), also from Erins paper
% detector specific params
if strcmp(detector, '')
    discharge_tol=0.005; % taken from spike function
    win = 0.05; % size of the window to look for the minimum number of channels, in seconds
    seq = 0.015; % 15ms for spikes within a sequence, taken from Erin Conrads Brain paper
elseif contains(detector, 'param1')
    win = 0.03; % size of the window to look for the minimum number of channels, in seconds
    seq = 0.05; % 15ms for spikes within a sequence, taken from Erin Conrads Brain paper
elseif contains(detector, 'param2')
    win = 0.1; % size of the window to look for the minimum number of channels, in seconds
    seq = 0.03; % 15ms for spikes within a sequence, taken from Erin Conrads Brain paper
elseif contains(detector, 'delphos')
    spike_srate = 200;
    win = 0.05; % size of the window to look for the minimum number of channels, in seconds
    seq = 0.015; % 15ms for spikes within a sequence, taken from Erin Conrads Brain paper
end

n_spikes = [];
% for catching errors
errors = struct('files', [], 'message', []);

for r = 1:numel(releases)
    release = releases(r);
    
    release_dir = [top_dir, 'release', release '/'];
    
    % remove parent and hidden directories, then get protocols
    folders = dir([release_dir '/protocols']);
    folders = {folders([folders.isdir]).name};
    protocols = folders(cellfun(@(x) ~contains(x, '.'), folders));
    
    for p = 1:numel(protocols)
        protocol = protocols{p};
        
        % get global info struct
        fname = [release_dir 'protocols/', protocol, '.json'];
        fid = fopen(fname);
        raw = fread(fid);
        str = char(raw');
        fclose(fid);
        info = jsondecode(str);
        eval(['info = info.protocols.', protocol,';']);
        
        % get subjects
        subjects = fields(info.subjects);
        for s = 1:numel(subjects)
            subj = subjects{s};
            
            % save command window
            %clc
            if ~exist([top_dir, 'processed/release',release, '/', protocol, '/', subj, '/'], 'dir')
                mkdir([top_dir, 'processed/release',release, '/', protocol, '/', subj, '/']);
            end
            %eval(['diary ', [top_dir, 'processed/release',release, '/', protocol, '/', subj, '/log.txt']]);
            
            fprintf('\n******************************************\nStarting IED detection for subject %s...\n', subj)
            
            % get experiements
            eval(['experiments = fields(info.subjects.' subj, '.experiments);'])
            for e = 1:numel(experiments)
                exper = experiments{e};
                
                % get seesions
                eval(['sessions = fields(info.subjects.' subj, '.experiments.', exper, '.sessions);'])
                for n = 1:numel(sessions)
                    
                    sess = sessions{n};
                    sess = strsplit(sess, 'x');
                    sess = sess{end};
                    % get the path names for this session, loaded from a json file
                    eval(['curr_info = info.subjects.' subj, '.experiments.' exper, '.sessions.x', sess, ';'])
                    
                    % folders
                    save_dir = [top_dir, 'processed/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
                    img_dir = [top_dir, 'img/spikes/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
                    if ~exist(img_dir, 'dir')
                        mkdir(img_dir);
                    end
                    
                    % check if this subect has clean data
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
                        %initialize
                        out_clean = [];
                        marker = [];
                        
                        % get spikes
                        if strcmp(detector,'') || contains(detector, 'param')
                            
                            for j = 1:nTrial
                                % initialize
                                out_clean(j).pos = 0;
                                out_clean(j).dur = 0;
                                out_clean(j).chan = 0;
                                out_clean(j).weight = 0;
                                out_clean(j).con = 0;
                                out_clean(j).seq = 0;
                                % run detection alg
                                try
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
                                    n_spikes = [n_spikes; numel(kept_spike)/(size(MARKER.M,2)/MARKER.fs)];
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
                                    
                                 catch ME
                                     
                                     errors(end+1).files = [subj, '_', exper, '_', sess];
                                     errors(end).message = ME.message;
                                 end
                                
                            end
                            % save
                            if ~isempty(out_clean)
                                save([save_dir, 'spike_info_', num2str(win), '.mat'], 'win', 'out_clean', 'marker');
                            end
                        else
                            for j = 1:nTrial
                                curr = [];
                               % try
                                    if strcmp(detector, '_delphos_auto')
                                        results = Delphos_detector(ft_data.trial{j},ft_data.label, 'SEEG', ft_data.fsample, {'Spk'}, [], [], 50,[]);
                                    else
                                        results = Delphos_detector(ft_data.trial{j},ft_data.label, 'SEEG', ft_data.fsample, {'Spk'}, [], [], 'auto',[]);
                                    end
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
                                    out_clean(j).seq = 0;
                                    seq_cnt = 0;
                                    include_length = win;%.300*MARKER.fs;
                                    nSamp = size(ft_data.trial{j},2);
                                    nSpike = numel(curr.pos);
                                    kept_spike = false(size(curr.pos));
                                    
                                    for i = 1:nSpike
                                        curr_pos = curr.pos(i);
                                        
                                        if kept_spike(i) == 0
                                            win_spike = (curr.pos > curr_pos & curr.pos < (curr_pos + win));
                                            % add spikes within 15ms of the
                                            % last one
                                            last_spike = max(curr.pos(win_spike));
                                            curr_sum = 0;
                                            while curr_sum < sum(win_spike) % stop when you stop adding new spikes
                                                curr_sum = sum(win_spike);
                                                win_spike = win_spike | (curr.pos > last_spike & curr.pos < (last_spike + seq));
                                                last_spike = max(curr.pos(win_spike));
                                            end
                                            win_chan = curr.chan(win_spike);

                                            % set sequence ID for all spikes
                                            % in this window
                                            seqs = struct('idx',[],'chan',[]);
                                            if sum(win_spike) > 0
                                                [~,leader_idx] = min(curr.pos(win_spike));
                                                leader = win_chan(leader_idx);
                                                if sum(win_chan == leader) == 1
                                                    curr.seq(win_spike) = seq_cnt;
                                                    seqs(1).idx = find(win_spike);
                                                    seqs(1).chan = win_chan;
                                                    seq_cnt = seq_cnt + 1;
                                                else
                                                    % parse sequence at the
                                                    % leader.
                                                    end_pts = find(win_chan == leader);
                                                    end_pts = [end_pts, numel(win_chan) + 1];
                                                    win_idx = find(win_spike);
                                                    for m = 1:(numel(end_pts)-1)
                                                        seqs(m).chan = win_chan(end_pts(m):(end_pts(m+1)-1));
                                                        seqs(m).idx = win_idx(end_pts(m):(end_pts(m+1)-1));
                                                        curr.seq(seqs(m).idx) = seq_cnt;
                                                        seq_cnt = seq_cnt + 1;
                                                    end
                                                end
                                            end
                                            % for each sequence, remove events that generalize
                                            % to 80% of elecs within 2ms,
                                            % keep if it spread to at least
                                            % 3 channels
                                            for m = 1:numel(seqs)
                                                time_between = diff(curr.pos(seqs(m).idx));        
                                                if (numel(unique(seqs(m).chan)) >= min_chan) && ~(numel(unique(seqs(m).chan(time_between <= thr))) >= nChan*.5)
                                                    kept_spike(seqs(m).idx) = true;
                                                end
                                            end
                                        end
                                    end
                                    % select only good spikes
                                    out_clean(j).pos = curr.pos(kept_spike);
                                    out_clean(j).dur = curr.dur(kept_spike);
                                    out_clean(j).chan = curr.chan(kept_spike);
                                    out_clean(j).seq = curr.seq(kept_spike);
                                    n_spikes = [n_spikes; numel(kept_spike)/(size(ft_data.trial{j},2)*ft_data.fsample)];
                                    fprintf('This dataset had %d IEDs per second\n', numel(kept_spike)/(size(ft_data.trial{j},2)/ft_data.fsample))
                                    
                                    
                                    % get new M
                                    m = zeros(nChan, ceil(size(ft_data.trial{j},2)/ft_data.fsample*spike_srate));
                                    for i=1:numel(out_clean(j).pos)
                                        m(out_clean(j).chan(i),round(out_clean(j).pos(i)*spike_srate))=1;
                                    end
                                    marker(j).m_clean = m;
                                    marker(j).fs = spike_srate;
%                                  catch ME
%                                      errors(end+1).files = [subj, '_', exper, '_', sess];
%                                      errors(end).message = ME.message;
%                                  end
                                % save
                                if ~isempty(out_clean)
                                    save([save_dir, 'spike_info', detector, '.mat'], 'out_clean', 'marker', 'min_chan', 'win');
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

% remove empty entry
errors = errors(2:end);
save([top_dir, 'spike_errors', detector, '.mat'], 'errors');
save([top_dir, 'n_spikes', detector, '.mat'], 'n_spikes');
