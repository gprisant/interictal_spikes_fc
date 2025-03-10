clear

% global variables
top_dir = '/Volumes/bassett-data/Jeni/RAM/';

releases = ['1', '2', '3'];

spike_win = 0.05; %for loading spike data
win_length = 1; % in seconds
detector = '_delphos';
for r = 1:numel(releases)
    release = releases(r);
    
    release_dir = [top_dir, 'release', release '/'];
    
    % remove parent and hidden directories, then get protocols
    folders = dir([release_dir '/protocols']);
    folders = {folders([folders.isdir]).name};
    protocols = folders(cellfun(@(x) ~contains(x, '.'), folders));
    
    % just for testing that qsub fuction will work
    for p = 1:numel(protocols)
        protocol = protocols{p};
        
        % get global info struct
        fname = [release_dir 'protocols/', protocol, '.json'];
        fid = fopen(fname);
        raw = fread(fid);
        str = char(raw');
        fclose(fid);
        info = jsondecode(str);
        info = info.protocols.r1;
        
        % get subjects
        subjects = fields(info.subjects);
        for s = 1:numel(subjects)
            subj = subjects{s};
            % main function for functional connectivity - helps with paralelizing
            
            release_dir = [top_dir, 'release', release '/'];
            
            % get global info struct
            fname = [release_dir 'protocols/', protocol, '.json'];
            fid = fopen(fname);
            raw = fread(fid);
            str = char(raw');
            fclose(fid);
            info = jsondecode(str);
            eval(['info = info.protocols.', protocol,';']);
            
            % subjects not to use
            load([top_dir, 'bad_datasets.mat'])
            errors = struct('files', [], 'message', []);
            
            % make subject directory
            subj_dir = [top_dir, 'FC/release',release, '/', protocol, '/', subj, '/'];
            if ~exist(subj_dir, 'dir')
                mkdir(subj_dir);
            end
            
            if ~exist([top_dir, 'processed/release',release, '/', protocol, '/', subj, '/'], 'dir')
                mkdir([top_dir, 'processed/release',release, '/', protocol, '/', subj, '/']);
            end
            
            fprintf('\n******************************************\nStarting WM for subject %s...\n', subj)
            
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
                    data_dir = [top_dir, 'processed/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
                    
                    
                    if exist([data_dir, 'channel_info.mat'], 'file')
                        load([data_dir, 'data_clean.mat'])
                        load([data_dir, 'channel_info.mat'])
                        eval(['curr_info = info.subjects.' subj, '.experiments.' exper, '.sessions.x', sess, ';'])
                        % get file info struct - this file has names, channel index, and positions
                        % in space. It does not have categories (SOZ, interictal, etc)
                        fid = fopen([release_dir, curr_info.contacts]);
                        raw = fread(fid);
                        channel_info = jsondecode(char(raw'));
                        code = fields(channel_info); % sometimes this doen't match subject
                        eval(['channel_info = channel_info.',  code{1}, ';'])
                        fclose(fid);
                        
                        % get numbers so that you can load the correct files. Don't assume they are
                        % in the same order (they usually arent)
                        wm_reg = cell(numel(ft_data.label),1);
                        for i = 1:numel(wm_reg)
                            chann = ft_data.label{i};
                            try
                                eval(['wm_reg{i} = channel_info.contacts.', chann, '.atlases.wb.region;'])
                                eval(['wm_reg_unique{i} = channel_info.contacts.', chann, '.atlases.wb.region;'])
                            catch
                                try
                                    eval(['wm_reg{i} = channel_info.contacts.', chann, '.atlases.whole_brain.region;'])
                                    eval(['wm_reg_unique{i} = channel_info.contacts.', chann, '.atlases.whole_brain.region;'])
                                catch
                                    wm_reg{i} = '';
                                end
                            end
                        end
                        wm = cellfun(@(x) contains(lower(x),'white matter'), wm_reg);
                        wm(1);
                        fprintf('\n This subj has %d WM contacts', sum(wm));
                        save([data_dir, 'channel_info.mat'], 'wm',  'channel_info', 'soz', 'interictal_cont', 'labels', 'chann_idx', 'regions', 'mni_coords', 'elec_type');
                    end
                end
            end
        end
    end
end

