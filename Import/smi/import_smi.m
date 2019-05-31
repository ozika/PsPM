function [data] = import_smi(varargin)
%Function for importing SMI data generated by an iView eyetracker. The
%function changes the importing method depending on input the arguments. If an
%event file has been generated by the eyetracker software and is
%passed as an argument, import_SMI will also import the events and store
%them in the ouput struct, otherwise no information about blinks and saccades are generated.
%Gaze values while blinks or saccades are set to NaN
%
% FORMAT:
% data = import_eyelink(sample_file, event_file)
%   sample_file: path to the file which contains the recorded SMI Data File
%                in ASCII file format
%   event_file:  path to the file which contains the computed events of the
%                recorded SMI Data File in ASCII file format
%__________________________________________________________________________
%
% (C) 2019 Laure Ciernik
% Function uses import function from the GazeVisToolbox �.

if isempty(varargin)
    warning('ID:invalid_input', 'import_SMI.m needs at least one input sample_file.'); return;
end

event_ex =false;
if numel(varargin)==1
    sample_file = varargin{1};
    % check for the existence of sample_file
    if exist(sample_file,'file')
        warning(['Import_SMI will only return, pupil data. ',...
            'No information about blinks, saccades or will be generated. ',...
            'In order to generate this information, you have to pass an event file.']);
    else
        warning('ID:invalid_input', 'Passed sample_file does not exist.'); return;
    end
elseif numel(varargin)==2
    sample_file = varargin{1};
    events_file = varargin{2};
    event_ex=true;
    % check for the existence of sample_file and event_file
    if ~exist(sample_file,'file')
        warning('ID:invalid_input', 'Passed sample_file does not exist.'); return;
    elseif ~exist(events_file,'file')
        warning('ID:invalid_input', ['Passed event_file does not exist. ',...
            'Result will not include event information.']);
        event_ex = false;
    end
else
    warning('ID:invalid_input', 'import SMI has too many input arguments.'); return;
end
%% open sample_file
fileID_sample = fopen(sample_file, 'rt');
fline_sample = fgetl(fileID_sample);
%% get sample_file header
headr_ctr = 1;
header_sample{headr_ctr} = fline_sample;
while contains(fline_sample,'##')
    headr_ctr = headr_ctr + 1;
    fline_sample = fgetl(fileID_sample);
    header_sample{headr_ctr} = fline_sample;
end
header_sample = header_sample';
%% check columns of data
% last line of the header descibes the columns contained in the importfile
% (can be variable depending recodrings)
columns = strsplit(fline_sample, '\t');
POR_available = any(cell2mat(cellfun(@(x) contains(x,'POR'),columns,'uniformoutput',false)));
if ~POR_available
    warning('ID:invalid_input', ['Passed sample_file does not contain eye ',...
        'position data mapped to the calibration area. The data will ',...
        'contain only raw data for the eye-position. No range for the data available.']);
end

%% process header informations
% record time
datePos = strncmpi(header_sample, '## Date', 7);
dateFields = regexp(header_sample{datePos}, '\s+', 'split');
% sample rate
sr_pos = strncmpi(header_sample, '## Sample Rate',14);
sr_field = regexp(header_sample{sr_pos}, '\s+', 'split');
sr = str2double(sr_field{4});
% gaze information
% calibration area
cal_a_pos = strncmpi(header_sample, '## Calibration Area',19);
if~isempty(cal_a_pos)
    cal_field = regexp(header_sample{cal_a_pos}, '\s+', 'split');
    xmax = str2double(cal_field{4});
    ymax = str2double(cal_field{5});
else
    xmax=[];
    ymax=[];
end
% calibration points
cal_p_pos = strncmpi(header_sample, '## Calibration Point',20);
if~isempty(cal_p_pos)
    CP = header_sample(cal_p_pos);
    CP_open = cell2mat(cellfun(@(x)regexpi(x,'('),CP,'uniformoutput',0));
    CP_close = cell2mat(cellfun(@(x)regexpi(x,')'),CP,'uniformoutput',0));
    for i=1:length(CP)
        CP_inf{i}=CP{i}(CP_open(i)+1:CP_close(i)-1);
    end
    CP_inf = cellfun(@(x) strsplit(x,';'),CP_inf,'uniformoutput',0);
    CP_inf = cellfun(@(x) cellfun(@(y) str2double(y),x,'uniformoutput',0),CP_inf,'uniformoutput',0);
    CP_inf = cellfun(@(x) x',CP_inf,'uniformoutput',0);
    calibration_points = cell2mat([CP_inf{:}]');
else
    calibration_points=[];
end

% eyes observed
format_pos = strncmpi(header_sample, '## Format',9);
comma_pos = regexp(header_sample{format_pos}, ',');
temp = header_sample{format_pos};
temp(comma_pos)=[];
format_fields = regexp(temp, '\s+', 'split');
l_eye = any(cell2mat(cellfun(@(x)strcmpi(x,'LEFT'),format_fields,'UniformOutput',0)));
r_eye = any(cell2mat(cellfun(@(x)strcmpi(x,'RIGHT'),format_fields,'UniformOutput',0)));
if l_eye && r_eye
    eyesObserved = 'LR';
elseif l_eye
    eyesObserved = 'L';
else
    eyesObserved = 'R';
end
% Stimulus dimension
sd_pos = strncmpi(header_sample, '## Stimulus Dimension',21);
sd_field = regexp(header_sample{sd_pos}, '\s+', 'split');
stimulus_dimension = [str2double(sd_field{5}),str2double(sd_field{6})];
stimulus_dimension_unit = sd_field{4}(2:3);

% Head distance
hd_pos = strncmpi(header_sample, '## Head Distance',16);
hd_field = regexp(header_sample{hd_pos}, '\s+', 'split');
head_distance = str2double(hd_field{5});
head_distance_unit = hd_field{4}(2:3);

%% get data part of sample file
% create right fomart for import
formatSpec = repmat('%s',1,numel(columns));
%read in sample_file
datastr = textscan(fileID_sample,formatSpec , 'delimiter', '\t');
fclose(fileID_sample);
% data part
datastr = [datastr{:}];

%% open events_file, get events, and events header
if event_ex
    % add the toolbox used for the event evaluation onto the search path
    addpath('GazeVisToolbox');
    % get events from event file
    [eventsRaw,smiParams2] = ReadSmiEvents_custom(events_file);
    
    % get right format
    % get names of fields
    event_fields = fieldnames(eventsRaw);
    % find idx of Blinks and Saccade fields
    blinks_idx = cell2mat(cellfun(@(x)strcmpi(x,'Blinks'),event_fields,'UniformOutput',0));
    saccade_idx= cell2mat(cellfun(@(x)strcmpi(x,'Saccades'),event_fields,'UniformOutput',0));
    
    % get field names of Blink and Saccade struct
    blink_fields =fieldnames(eventsRaw.(event_fields{blinks_idx}));
    saccade_fields=fieldnames(eventsRaw.(event_fields{saccade_idx}));
    
    % find idx of trial column in Blink and Saccade struct
    trial_blinks_idx = cell2mat(cellfun(@(x)strcmpi(x,'Trial'),blink_fields,'UniformOutput',0));
    trial_saccade_idx= cell2mat(cellfun(@(x)strcmpi(x,'Trial'),saccade_fields,'UniformOutput',0));
    
    % get trial column of Blinks and Saccade -> used later line 273/274
    trial_ids_blink_sess = eventsRaw.(event_fields{blinks_idx}).(blink_fields{trial_blinks_idx});
    trial_ids_sacc_sess = eventsRaw.(event_fields{saccade_idx}).(blink_fields{trial_saccade_idx});
    
    if strcmpi(eyesObserved,'LR')
        %find left eye blinks
        L_idx = cell2mat(cellfun(@(x)~isempty(regexp(x,'L')),eventsRaw.(event_fields{blinks_idx}).(blink_fields{1}),'UniformOutput',0));
        %find right eye blinks
        R_idx = cell2mat(cellfun(@(x)~isempty(regexp(x,'R')),eventsRaw.(event_fields{blinks_idx}).(blink_fields{1}),'UniformOutput',0));
        %find blinks on both eyes
        B_idx = cell2mat(cellfun(@(x) length(regexp(x,'B'))==2,eventsRaw.(event_fields{blinks_idx}).(blink_fields{1}),'UniformOutput',0));
        %include the blinks of both eyes in separeted channels
        L_blink_idx = L_idx;
        L_blink_idx(B_idx)=true;
        R_blink_idx = R_idx;
        R_blink_idx(B_idx)=true;
        %find left eye saccades
        L_idx = cell2mat(cellfun(@(x)~isempty(regexp(x,'L')),eventsRaw.(event_fields{saccade_idx}).(saccade_fields{1}),'UniformOutput',0));
        %find right eye saccades
        R_idx = cell2mat(cellfun(@(x)~isempty(regexp(x,'R')),eventsRaw.(event_fields{saccade_idx}).(saccade_fields{1}),'UniformOutput',0));
        %find saccades on both eyes
        B_idx = cell2mat(cellfun(@(x)~isempty(regexp(x,'B')),eventsRaw.(event_fields{saccade_idx}).(saccade_fields{1}),'UniformOutput',0));
        %include the saccades of both eyes in separeted channels
        L_saccades_idx = L_idx;
        L_saccades_idx(B_idx)=true;
        R_saccades_idx = R_idx;
        R_saccades_idx(B_idx)=true;
    end
    
    % remove toolbox from path
    rmpath('GazeVisToolbox');
end

%% get pupil method and units
% mapped pupil diameter [mm]
MD = find(cell2mat(cellfun(@(x) contains(x,'Mapped Diameter'),columns,'UniformOutput',0)));
% pupil area in [mm] or [px]
A  = find(cell2mat(cellfun(@(x) contains(x,'Area'),columns,'UniformOutput',0)));
% pupil diameter in [mm] or [px] -> area based or bounding box
D  = find(cell2mat(cellfun(@(x) contains(x,'Dia'),columns,'UniformOutput',0)));
% always try to use mapped diameter dirst
if ~isempty(MD)
    pupilUnit = 'diameter in mm';
    pupil_channels = MD;
elseif ~isempty(A)
    pupilUnit = get_pupil_unit(columns{A(1)},'area');
    pupil_channels = A;
else
    %check if area based diameter
    if length(D)==3||length(D)==6
        pupilUnit = get_pupil_unit(columns{D(3)},'diameter');
        if length(D)==3
            pupil_channels = D(3);
        else
            pupil_channels = D([3,6]);
        end
    else % safe diameter as 2 columns which hold width and heigth of bouding box
        pupilUnit = get_pupil_unit(columns{D(1)},'diameter');
        pupil_channels=D;
    end
end
% later we remove the Type column, thus the column indicies are shifted by
% one
pupil_channels=pupil_channels-1;

%% get all messages - if Event file is given take messages of event file otherwise read from file

messageCols = {'Time','Type','Trial','Text'};
messageKeyword = 'MSG';
idx_of_type = strcmpi(columns,'Type');
if event_ex
    event_idx = cell2mat(cellfun(@(x)strcmpi(x,'UserEvents'),event_fields,'UniformOutput',0));
    usr_events = eventsRaw.(event_fields{event_idx});
    nr_events = length(usr_events.Trial);
    msgs = cell(nr_events,4);
    for i=1:nr_events
        msgs(i,:) = {usr_events.Start(i),usr_events.EventType{i},usr_events.Trial(i),usr_events.Description{i}};
    end
else
    msg_idx =cell2mat(cellfun(@(x)strcmpi(x,messageKeyword),datastr(:,idx_of_type),'UniformOutput',0));
    % get idx of messages
    msg_idx = find(msg_idx);
    % save all messages in variable
    msgs = cell(numel(msg_idx),numel(messageCols));
    for i=1:numel(msg_idx)
        msgs(i,:)= datastr(msg_idx(i),1:4);
    end
end

%% find number of recordings / sessions and split
idx_of_trials = strcmpi(columns,'Trial');
trials =cell2mat(cellfun(@(x)str2double(x),datastr(:,idx_of_trials),'UniformOutput',0));
offsets = find(diff(trials));
if isempty(offsets)
    fprintf('File contains single trial.\n');
    offsets = length(datastr(:, 1));
else
    offsets(end+1)= length(datastr(:, 1));
end
onsets = [1; offsets+1];
data = cell(numel(offsets),1);
%% convert data, compute blink, saccade and messages
for sn = 1:numel(offsets)
    data{sn} = struct();
    
    sn_data = datastr(onsets(sn):offsets(sn), :);
    
    % remove type column
    temp =sn_data;
    temp(:,idx_of_type)=[];
    
    % convert to single cell array (one cell per line)
    str_data = cell(size(temp, 1), 1);
    for iline = 1:size(str_data, 1)
        str_data{iline} = sprintf('%s ', temp{iline,:});
    end
    
    % concatenate strings and replace/interpret dots with NaN values
    str_data = strrep(str_data, ' . ', ' NaN ');
    
    %     datanum = str2double(temp);
    datanum = NaN(size(temp,1), size(temp,2));
    
    % convert numeric rows to numeric
    for n_row = 1:size(temp,1)
        data_num_row = sscanf(str_data{n_row}, '%f');
        n_cols = min(size(temp,2),numel(data_num_row));
        datanum(n_row,1:n_cols) = data_num_row(1:n_cols);
    end
    
    %% try to read some header information
    
    data{sn}.record_date  = dateFields{3};
    data{sn}.record_time  = dateFields{4};
    data{sn}.sampleRate   = sr;
    data{sn}.eyesObserved = eyesObserved;
    data{sn}.stimulus_dimension = stimulus_dimension;
    data{sn}.stimulus_dimension_unit = stimulus_dimension_unit;
    data{sn}.head_distance = head_distance;
    data{sn}.head_distance_unit = head_distance_unit;
    data{sn}.POR_available = POR_available;
    
    % only usefull information when POR data is available
    data{sn}.gaze_coords.xmin = 0;
    data{sn}.gaze_coords.xmax = xmax;
    data{sn}.gaze_coords.ymin = 0;
    data{sn}.gaze_coords.ymax = ymax;
    data{sn}.calibration_points=calibration_points;

    
    
    %% if even_file is given, include blinkes and saccades
    if event_ex
        % get time of first sample in current trail
        %         time = datanum(1,1);
        times= datanum(:,1);
        
        Blinks = eventsRaw.(event_fields{blinks_idx});
        Saccades = eventsRaw.(event_fields{saccade_idx});
        
        %take only blinks and saccades in correct trial
        b_trial_sess = trial_ids_blink_sess == sn;
        s_trial_sess = trial_ids_sacc_sess  == sn;
        
        % store the indicies in right format
        % ignore_str_pos = { {start_blink_l,end_blink_l,start_blink_r,end_blink_r},
        %                    {start_saccade_l,end_saccade_l,start_saccade_r,end_saccade_r} }
        ignore_str_pos = cell(2,1);
        ignore_str_pos{1}=cell(4,1);
        ignore_str_pos{2}=cell(4,1);
        
        if strcmpi(eyesObserved,'LR')
            %take into account, which blinks and saccades belong to which
            %eye
            val_blink_l   = b_trial_sess & L_blink_idx;
            val_blink_r   = b_trial_sess & R_blink_idx;
            val_saccade_l = s_trial_sess & L_saccades_idx;
            val_saccade_r = s_trial_sess & R_saccades_idx;
            
            % alwas add the time of the beginning of the current trial
            % since the measured start and end times are relative to the
            % time of the beginning ot the current trial
            
            start_blink_l = Blinks.Start(val_blink_l);%+time;
            end_blink_l = Blinks.End(val_blink_l);%+time;
            [ignore_str_pos{1}{1},ignore_str_pos{1}{2}]=get_idx(times,start_blink_l,end_blink_l);
            
            start_blink_r = Blinks.Start(val_blink_r);%+time;
            end_blink_r = Blinks.End(val_blink_r);%+time;
            [ignore_str_pos{1}{3},ignore_str_pos{1}{4}]=get_idx(times,start_blink_r,end_blink_r);
            
            start_saccade_l = Saccades.Start(val_saccade_l);%+time;
            end_saccade_l = Saccades.End(val_saccade_l);%+time;
            [ignore_str_pos{2}{1},ignore_str_pos{2}{2}]=get_idx(times,start_saccade_l,end_saccade_l);
            
            start_saccade_r = Saccades.Start(val_saccade_r);%+time;
            end_saccade_r = Saccades.End(val_saccade_r);%+time;
            [ignore_str_pos{2}{3},ignore_str_pos{2}{4}]=get_idx(times,start_saccade_r,end_saccade_r);
            
            
        else% always add the time of the beginning of the current trial
            % since the measured start and end times are relative to the
            % time of the beginning ot the current trial
            start_blink = Blinks.Start(b_trial_sess);%+time;
            end_blink = Blinks.End(b_trial_sess)+time;
            
            start_saccade = Saccades.Start(s_trial_sess);%+time;
            end_saccade = Saccades.End(s_trial_sess);%+time;
            
            if strcmpi(eyesObserved,'L')
                [ignore_str_pos{1}{1},ignore_str_pos{1}{2}]=get_idx(times,start_blink,end_blink);
                [ignore_str_pos{2}{1},ignore_str_pos{2}{2}]=get_idx(times,start_saccade,end_saccade);
            else
                [ignore_str_pos{1}{3},ignore_str_pos{1}{4}]=get_idx(times,start_blink,end_blink);
                [ignore_str_pos{2}{3},ignore_str_pos{2}{4}]=get_idx(times,start_saccade,end_saccade);
            end
        end
        
        % add blinks and saccades to datanum
        for i=1:numel(data{sn}.eyesObserved)
            
            % cycle through epoch types (saccades and blinks)
            for j = 1:numel(ignore_str_pos)
                
                % for later use when saccades and blinks should be separated
                idx_corr = 2*(j-1);
                
                % set indexes according to eye being processed
                if strcmpi(data{sn}.eyesObserved(i), 'L')
                    eye_corr = 0;
                    idx = (size(datanum,2)+1) + idx_corr;
                else
                    eye_corr = 2;
                    idx = (size(datanum,2)+2) + idx_corr;
                end
                
                % where to look for start and stop idx
                ep_start = 1 + eye_corr;
                ep_stop  = 2 + eye_corr;
                
                for k = 1:length(ignore_str_pos{j}{ep_start})
                    
                    start_pos = ignore_str_pos{j}{ep_start}(k);
                    stop_pos = ignore_str_pos{j}{ep_stop}(k) + ep_offset;
                    
                    if stop_pos > size( datanum, 1 ) && start_pos <= 0
                        % everything is a blink
                        datanum(1 : end, idx) = 1;
                    else
                        datanum(start_pos : stop_pos, idx) = 1;
                    end
                end
                
            end
        end
    end
    
    %% identify messages
    % translate MSG into double
    % look for general (gen) positions of MSG fields
    % look for specific (spe) MSG text and add it to a additional column to the
    % gen pos
    % take only messages from correct session
    idx_msg_trials = strcmpi(messageCols,'Trial');
    if event_ex
        msg_trials = usr_events.Trial;
        s_vec = usr_events.Time;%datanum(1,1);
        [s_idx,~]= get_idx(datanum(:,1),s_vec,s_vec);
        str_gen_pos =s_idx;
    else
        % take idx computed above
        str_gen_pos = msg_idx;
        msg_trials =cell2mat(cellfun(@(x)str2double(x),msgs(:,idx_msg_trials),'UniformOutput',0));
    end
    val_msg_idx = msg_trials==sn;
    
    % get only valid positions and shift according to the onset
    str_gen_pos = str_gen_pos(val_msg_idx);
    str_gen_pos = str_gen_pos-(onsets(sn)-1);
    
    % retrieve message strings from current session
    msg_str =  msgs(val_msg_idx,4);
    msg_str_idx = cell2mat(cellfun(@(x) find(x==':',1,'first'),msg_str,'UniformOutput',0));
    for u=1:length(msg_str_idx)
        msg_str{u} = msg_str{u}(msg_str_idx(u)+2:end);
    end
    % look for uniqueness of messages
    messages = unique(msg_str);
    
    % we assume each MSG has a specific text message
    % for each general position we fix the kind of message text
    str_spe_pos = zeros(length(str_gen_pos), 1);
    for j = 1:size(messages,1)
        for m = 1:size(str_gen_pos,1)
            s = regexp(sn_data{str_gen_pos(m,1),4}, ...
                messages(j), 'once');
            if s{1} > 0
                str_spe_pos(str_gen_pos(m,1),1) = j;
            end
        end
    end
    
    % add messages in colums of datanum
    str_gen_pos_plus = str_gen_pos + 1;
    datanum(str_gen_pos_plus,end+1) = 1;
    datanum(str_gen_pos_plus, end+1) = str_spe_pos(str_gen_pos,1);
    
    %% remove lines containing NaN (i.e. pure text lines) so that lines have a time interpretation
    data{sn}.raw = datanum;
    data{sn}.raw(isnan(datanum(:,3)),:) = [];
    % save column heder of raw data
    columns(2)=[];
    data{sn}.raw_columns=columns;
    
    if strcmpi(data{sn}.eyesObserved, 'LR')
        % pupilL, pupilR, xL, yL, xR, yR, blinkL, blinkR, saccadeL,
        % saccadeR
        % get idx of different channel
        if POR_available
            POR_xL = find(cell2mat(cellfun(@(x)contains(x,'L POR X'),data{sn}.raw_columns,'UniformOutput',0)),1);
            POR_yL = find(cell2mat(cellfun(@(x)contains(x,'L POR Y'),data{sn}.raw_columns,'UniformOutput',0)),1);
            POR_xR = find(cell2mat(cellfun(@(x)contains(x,'R POR X'),data{sn}.raw_columns,'UniformOutput',0)),1);
            POR_yR = find(cell2mat(cellfun(@(x)contains(x,'R POR Y'),data{sn}.raw_columns,'UniformOutput',0)),1);
        end
        xL = find(cell2mat(cellfun(@(x)contains(x,'L Raw X'),data{sn}.raw_columns,'UniformOutput',0)),1);
        yL = find(cell2mat(cellfun(@(x)contains(x,'L Raw Y'),data{sn}.raw_columns,'UniformOutput',0)),1);
        xR = find(cell2mat(cellfun(@(x)contains(x,'R Raw X'),data{sn}.raw_columns,'UniformOutput',0)),1);
        yR = find(cell2mat(cellfun(@(x)contains(x,'R Raw Y'),data{sn}.raw_columns,'UniformOutput',0)),1);
        
        
        if event_ex
            blinkL = size(data{sn}.raw,2)-5;
            blinkR = size(data{sn}.raw,2)-4;
            saccadeL = size(data{sn}.raw,2)-3;
            saccadeR = size(data{sn}.raw,2)-2;
            
            if POR_available
                data{sn}.channels = data{sn}.raw(:, [pupil_channels,xL,yL,xR,yR,POR_xL,POR_yL,POR_xR,POR_yR,blinkL,blinkR,saccadeL,saccadeR]);
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based
                if length(pupil_channels)==2
                    data{sn}.units = {pupilUnit,pupilUnit, 'pixel', 'pixel', 'pixel', ...
                        'pixel','mm','mm','mm','mm','blink', 'blink', 'saccade', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,11)| data{sn}.channels(:, 13)) == 1, [1,3:4,7:8] ) = NaN;
                    data{sn}.channels( (data{sn}.channels(:,12)| data{sn}.channels(:, 14)) == 1, [2,5:6,9:10] ) = NaN;
                    data{sn}.POR_channels_idx = [7,8,9,10];
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'], [pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel', 'pixel', ...
                        'pixel','mm','mm','mm','mm', 'blink', 'blink', 'saccade', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,13)| data{sn}.channels(:, 15)) == 1, [1:2,5:6,9:10] ) = NaN;
                    data{sn}.channels( (data{sn}.channels(:,14)| data{sn}.channels(:, 16)) == 1, [3:4,7:8,11:12] ) = NaN;
                    data{sn}.POR_channels_idx = [9,10,11,12];
                end
            else
                data{sn}.channels = data{sn}.raw(:, [pupil_channels,xL,yL,xR,yR,blinkL,blinkR,saccadeL,saccadeR]);
                
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based
                if length(pupil_channels)==2
                    data{sn}.units = {pupilUnit,pupilUnit, 'pixel', 'pixel', 'pixel', ...
                        'pixel', 'blink', 'blink', 'saccade', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,7)| data{sn}.channels(:, 9)) == 1, [1,3:4] ) = NaN;
                    data{sn}.channels( (data{sn}.channels(:,8)| data{sn}.channels(:, 10)) == 1, [2,5:6] ) = NaN;
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'], [pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel', 'pixel', ...
                        'pixel', 'blink', 'blink', 'saccade', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,9)| data{sn}.channels(:, 11)) == 1, [1:2,5:6] ) = NaN;
                    data{sn}.channels( (data{sn}.channels(:,10)| data{sn}.channels(:, 12)) == 1, [3:4,7:8] ) = NaN;
                end
            end
            
        else
            if POR_available
                data{sn}.channels = data{sn}.raw(:, [pupil_channels,xL,yL,xR,yR,POR_xL,POR_yL,POR_xR,POR_yR]);
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based
                if length(pupil_channels)==2
                    data{sn}.units = {pupilUnit,pupilUnit, 'pixel', 'pixel', 'pixel', ...
                        'pixel','mm','mm','mm','mm'};
                    data{sn}.POR_channels_idx = [7,8,9,10];
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'],[pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel', 'pixel', ...
                        'pixel','mm','mm','mm','mm'};
                    data{sn}.POR_channels_idx = [9,10,11,12];
                end
            else
                data{sn}.channels = data{sn}.raw(:, [pupil_channels,xL,yL,xR,yR]);
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based
                if length(pupil_channels)==2
                    data{sn}.units = {pupilUnit,pupilUnit, 'pixel', 'pixel', 'pixel', ...
                        'pixel'};
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'],[pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel', 'pixel', ...
                        'pixel'};
                end
            end
        end
    else
        % get idx of channels
        if POR_available
            POR_x = find(cell2mat(cellfun(@(x)contains(x,'POR X'),data{sn}.raw_columns,'UniformOutput',0)),1);
            POR_y = find(cell2mat(cellfun(@(x)contains(x,'POR Y'),data{sn}.raw_columns,'UniformOutput',0)),1);
        end
        x = find(cell2mat(cellfun(@(x)contains(x,'Raw X'),data{sn}.raw_columns,'UniformOutput',0)),1);
        y = find(cell2mat(cellfun(@(x)contains(x,'Raw Y'),data{sn}.raw_columns,'UniformOutput',0)),1);
        
        
        if event_ex
            %distinguish eyes
            if strcmpi(data{sn}.eyesObserved, 'L')
                blink = size(data{sn}.raw,2)-5;
                saccade = size(data{sn}.raw,2)-3;
            else
                blink = size(data{sn}.raw,2)-4;
                saccade = size(data{sn}.raw,2)-2;
            end
            if POR_available
                data{sn}.channels = data{sn}.raw(:,[pupil_channels,x,y,POR_x,POR_y,blink,saccade]);
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based
                if length(pupil_channels)==1
                    data{sn}.units = {pupilUnit, 'pixel', 'pixel','mm','mm','blink', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,6)| data{sn}.channels(:, 7)) == 1, 1:5 ) = NaN;
                    data{sn}.POR_channels_idx = [4,5];
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel','mm','mm', 'blink', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,7)| data{sn}.channels(:, 8)) == 1, 1:6 ) = NaN;
                    data{sn}.POR_channels_idx = [5,6];
                end
            else
                data{sn}.channels = data{sn}.raw(:,[pupil_channels,x,y,blink,saccade]);
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based
                if length(pupil_channels)==1
                    data{sn}.units = {pupilUnit, 'pixel', 'pixel', 'blink', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,4)| data{sn}.channels(:, 5)) == 1, [1:3] ) = NaN;
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel', 'blink', 'saccade'};
                    % set blinks to NaN
                    data{sn}.channels( (data{sn}.channels(:,5)| data{sn}.channels(:, 6)) == 1, [1:4] ) = NaN;
                end
            end
            
        else
            if POR_available
                data{sn}.channels = data{sn}.raw(:,[pupil_channels,x,y,POR_x,POR_y]);
                if length(tmp)==1
                    data{sn}.units = {pupilUnit, 'pixel', 'pixel','mm','mm'};
                    data{sn}.POR_channels_idx = [4,5];
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel','mm','mm'};
                    data{sn}.POR_channels_idx = [5,6];
                end
            else
                data{sn}.channels = data{sn}.raw(:,[pupil_channels,x,y]);
                %here we need to distinguish the pupil recording method:
                %Bounding Box or Area based;
                if length(tmp)==1
                    data{sn}.units = {pupilUnit, 'pixel', 'pixel'};
                else
                    data{sn}.units = {[pupilUnit,' x'],[pupilUnit,' y'], 'pixel', 'pixel'};
                end
            end
        end
        
        
    end
    % translate makers back into special cell structure
    markers = cell(1,3);
    for i=1:3
        markers{1, i} = cell(length(data{sn}.raw), 1);
    end
    
    markers{1,2}(:) = {'0'};
    markers{1,3} = zeros( length(data{sn}.raw), 1);
    markers{1, 1} = data{sn}.raw(:, size(data{sn}.raw,2)-1);
    marker_pos = find(markers{1,1} == 1);
    
    for i=1:length(marker_pos)
        % set to default value as long as there is no title provided
        % in the file
        markers{1, 2}{marker_pos(i)} = messages{data{sn}.raw(marker_pos(i), size(data{sn}.raw,2))};
        % there is no actual value
        % value has to be numeric
        markers{1, 3}(marker_pos(i)) = data{sn}.raw(marker_pos(i), size(data{sn}.raw,2));
    end
    
    % return markers
    data{sn}.markers = markers{1,1};
    data{sn}.markerinfos.name = markers{1,2};
    data{sn}.markerinfos.value = markers{1,3};
end
end
% function to find the idx of start and end
function [s_idx,end_idx]=get_idx(time_vec,s_vec,end_vec)
s_idx =arrayfun(@(x)find(x<time_vec,1), s_vec, 'UniformOutput', false);
end_idx =arrayfun(@(x)find(x>time_vec,1), end_vec, 'UniformOutput', false);
if isempty(s_idx)
    warning('ID:invalid_input', ['All values in the vector have ',...
        'starting times outside of the recording time. '],...
        'Please check your event file.'); return;
elseif isempty(end_idx)
    warning('ID:invalid_input', ['All values in the vector have ',...
        'ending times outside of the recording time. '],...
        'Please check your event file.'); return;
end
if numel(s_idx)>numel(end_idx)
    diff = numel(s_idx)-numel(end_idx);
    end_idx(end+1:end+diff)={[]};
end
for i=1:numel(s_idx)
    if end_idx{i}+1>length(time_vec)
        end_idx{i}=length(time_vec);
    elseif s_idx{i}-1 <1
        s_idx{i}=1;
    elseif s_idx{i}-1 >length(time_vec)
        s_idx{i}=length(time_vec);
    else
        s_idx{i}=s_idx{i}-1;
        end_idx{i}=end_idx{i}+1;
    end
end
s_idx=cell2mat(s_idx);
end_idx=cell2mat(end_idx);
end
function [unit] = get_pupil_unit(str,dia_or_area)
idx =  regexpi(str, '[');
unit = str(idx+1:end-1);
if contains(unit,'px')
    unit = [dia_or_area, ' units'];
else
    unit = [dia_or_area, ' in ',unit];
end
end
