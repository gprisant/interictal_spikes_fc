%% Get performance on behavioral tasks

clear
clc
close all
warning ON

addpath(genpath('/Users/stiso/Documents/Code/interictal_spikes_fc/'))
addpath('/Users/stiso/Documents/MATLAB/fieldtrip-20170830/')

%%

% global variables and packages
top_dir = '/Volumes/bassett-data/Jeni/RAM/';
eval(['cd ', top_dir])
tasks = [{'YC'},{'TH'},{'PAL'},{'catFR'},{'FR'}];
nTask = numel(tasks);
releases = ['1', '2', '3'];
% initialize table
task_table = cell2table(cell(0,6), 'VariableNames', [{'subj'},tasks]);

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
            % this subjects performance
            subj_perf = cell(nTask,1);
            
            subj = subjects{s};
            
            fprintf('task performance for subject %s...\n', subj)
            
            % get experiements
            eval(['experiments = fields(info.subjects.' subj, '.experiments);'])
            for e = 1:numel(experiments)
                exper = experiments{e};
                cat_exper = exper(isletter(exper));
                idx = find(strcmp(cat_exper, tasks));

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
                    save_dir = [top_dir, 'perf/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
                    subj_dir = [top_dir, 'perf/release',release, '/', protocol, '/', subj, '/'];
                    img_dir = [top_dir, 'img/perf/release',release, '/', protocol, '/', subj, '/', exper, '/', sess, '/'];
                    if ~exist(img_dir, 'dir')
                        mkdir(img_dir);
                    end
%                     if ~exist(save_dir, 'dir')
%                         mkdir(save_dir);
%                     end
%                     if ~exist([subj_dir, '/'], 'dir')
%                         mkdir([subj_dir, '/']);
%                     end
                    
                    if exist([data_dir, 'data_clean.mat'], 'file')
                        % get the path names for this session, loaded from a json file
                        eval(['curr_info = info.subjects.' subj, '.experiments.' exper, '.sessions.x', sess, ';'])
                        
                        % load event info
                        if isfield(curr_info, 'all_events') && exist([release_dir, curr_info.all_events],'file')
                            fid = fopen([release_dir, curr_info.all_events]);
                        elseif isfield(curr_info, 'task_events') && exist([release_dir, curr_info.task_events],'file')% some only have tasks events
                            fid = fopen([release_dir, curr_info.task_events]);
                        elseif exist([release_dir, 'protocols/', protocol, '/subjects/', subj, '/experiments/', exper, '/sessions/', sess, '/behavioral/current_processed/all_events.json'],'file') %if info has the wrong file
                            fid = fopen([release_dir, 'protocols/', protocol, '/subjects/', subj, '/experiments/', exper, '/sessions/', sess, '/behavioral/current_processed/all_events.json']);
                        elseif exist([release_dir, 'protocols/', protocol, '/subjects/', subj, '/experiments/', exper, '/sessions/', sess, '/behavioral/current_processed/task_events.json'],'file') %if info has the wrong file
                            fid = fopen([release_dir, 'protocols/', protocol, '/subjects/', subj, '/experiments/', exper, '/sessions/', sess, '/behavioral/current_processed/task_events.json']);
                        else
                            error('Could not find an events file')
                        end
                        raw = fread(fid);
                        events = jsondecode(char(raw'));
                        
                        switch cat_exper                            
                            case [{'catFR'},{'FR'}]
                                if strcmpi(exper, "FR3") || strcmpi(exper, "FR2")
                                    % remove stim
                                    events = events(strcmpi({events.type}, 'REC_WORD') & cellfun(@(x) x == 0, {events.is_stim}));
                                else
                                    events = events(strcmpi({events.type}, 'REC_WORD'));
                                end
                                subj_perf{idx} = [subj_perf{idx}, mean([events.recalled])];
                            case {'PAL'}
                                events = events(strcmpi({events.type}, 'REC_EVENT') & cellfun(@(x) x == 0, {events.stim_list}));
                                subj_perf{idx} = [subj_perf{idx}, mean([events.correct])];
                            case {'TH'}
                                events = events(cellfun(@(x) x > 0, {events.normErr}) & cellfun(@(x) x == 0, {events.stim_list}));
                                subj_perf{idx} = [subj_perf{idx}, mean([events.normErr])];
                            case {'YC'}
                               events = events(strcmpi({events.type}, 'NAV_TEST') & cellfun(@(x) x == 0, {events.is_stim}));
                               subj_perf{idx} = [subj_perf{idx}, mean([events.resp_performance_factor])];
                        end
                        
                    end
                end
            end
            subj_perf = cellfun(@(x) mean(x), subj_perf);
            task_table = [task_table; [cell2table({subj},'VariableNames', {'subj'}), array2table(subj_perf', 'VariableNames', tasks)]];
        end
    end
end

writetable(task_table, [top_dir, 'group_analysis/task_performance.csv'])