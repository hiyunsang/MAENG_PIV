%% Example 06b - multiprocessor/multicomputer treatment
% Due to various limitations, PIVsuite works mostly only on a single core of the computer. To improve
% performance when treating large sets of PIV images, it is advantageous to run several MATLAB instances in
% order to use all the power of the processor. Each running MATLAB can treat a different part of image
% sequence (the treatment of a part of image by a single Matlab instance is called "job").
%
% PIVsuite is able manage distribution of PIV image pairs to several jobs comfortably. This example
% demonstrates how to use this feature.

%% How to run this example
%
% * Before running this example, you might want to increase the number of image pairs in folder |../Data/Test
% Tububu| (e.g., by copying them with another name).
% * Start four independent Matlab instances on your computer.
% * Run simultaneously this example in each Matlab instance. Thus, there will be four Matlab windows running
% simultaneously the same example. PIVsuite, via subroutine pivManageJobs, will adjust each of Matlab instance
% to treat approximately one fourth of image pairs.
% * If something goes wrong (e.g., the user stops prematurely the treatment of some part of results), it is useful
% to erase lock files (extension .lck) in the output folder. For repeating the example, the user should erase all
% files from the output folder.
% * Most of Matlabs will only treat the image pairs and save data to the disk, without storing results of all
% the image sequence. Only one Matlab instances will "remember" the results of the sequence.
% * Running the example once more (after all image pairs are treated) will load the results from the files
% with results.
% 
% Other hints are:
% 
% * The treatment can be distributed also to several computers (typically if they access the same data on a
% shared disk via a network). In such a case, share a folder with data, and run some of matlabs on one computer
% and the remaining on another.
% * Total number of jobs is given by |pivPar.jmParallelJobs| option below. This parameter should correspond to
% the number of Matlab instances running this example. Generally, fastes treatment is obtained if the number
% of Matlab instances is the same as the number of available processor cores.
% * It is suitable to run several Matlab instances automatically from a command line in the Linux OS. A shell
% script for doing so is provided with this example (|startntimes.sh|).


%% Define image pairs to treat
% Initialize the variable |pivPar|, in which parameters of PIV algorithm (such as interrogation area size) are 
% defined. Initialize also variable |pivData|, to which results will be stored.

% Initialize variables
clear;
pivPar = [];                                              % variable for settings
pivData = [];                                             % variable for storing results
imagePath = '../Data/Test Tububu';  % folder with processed images (use slash (/) as path separator both on Windows 
                                    % and Unix platforms; do not use backslash (\), and do not use 'filesep')

% get list of images in the folder and sort them
aux = dir([imagePath, '/*.bmp']);                 
for kk = 1:numel(aux), fileList{kk} = [imagePath, '/', aux(kk).name]; end   %#ok<SAGROW>
fileList = sort(fileList);

% Define image pairs
pivPar.seqPairInterval = 1;     % all image pairs will be processed in this example
pivPar.seqSeqDiff = 1;          % the second image in each pair is one frame after the first image
[im1,im2] = pivCreateImageSequence(fileList,pivPar);

%% Settings for processing the first image pair
% These settings will be used only for processing of the first image pair:

pivParInit.iaSizeX = [64 32 32 32 32];      % interrogation area size for five passes
pivParInit.iaStepX = [32 16 12 12 12];      % grid spacing for five passes
pivParInit.qvPair = {...                    % define plot shown between iterations
    'Umag','clipHi',3,...                                 % plot displacement magnitude, clip to 3 px      
    'quiver','selectStat','valid','linespec','-k',...     % show valid vectors in black
    'quiver','selectStat','replaced','linespec','-w'};    % show replaced vectors in white
pivParInit = pivParams([],pivParInit,'defaults');   % set defaults as if treating single image pair

%% Settings for processing subsequent image pairs
% Subsequent image pairs will be trated with these settings:

pivPar.iaSizeX = [32 32];                 % IA size; carry only two iterations for subsequent image pairs
pivPar.iaStepX = [12 12];                 % grid spacing 
pivPar.anVelocityEst = 'previousSmooth';  % use smoothed velocity from previous image pair as velocity 
                                          % estimate for image deformation
pivPar.anOnDrive = true;                  % files with results will be stored in an output folder
pivPar.anTargetPath = [imagePath,'/pivOut_multicore'];
                                          % directory for storing results
pivPar.anForceProcessing = false;         % if false, only image pairs, for which no file with results is 
            % available, will be processed. Processing is skipped if file with results is available. If true,
            % processing is carried out even if result file is present. (Set this parameter to true if all
            % image pairs should be reprocessed, for example because of different setting of processing
            % parameters).
            
pivPar.qvPair = {...                      % define plot shown between iterations
    'Umag','clipHi',3,...                                 % plot displacement magnitude, clip to 3 px      
    'quiver','selectStat','valid','linespec','-k',...     % show valid vectors in black
    'quiver','selectStat','replaced','linespec','-w'};    % show replaced vectors in white

% Set all other parameters to defaults:

[pivPar, pivData] = pivParams(pivData,pivPar,'defaultsSeq');
            
%% Distribute treatment to several jobs
% Parameter |jmParallelJobs| defines, how many parallel jobs will be treating the image sequence (each job will
% treat a part of image pairs). Using soubroutine |pivManageJobs|, a part of image pair is attributed to the
% current job.

figure(1);
pivPar.jmParallelJobs = 4;
[im1,im2,pivPar] = pivManageJobs(im1,im2,pivPar);
[pivData] = pivAnalyzeImageSequence(im1,im2,pivData,pivPar,pivParInit);

%% Supress graphical output, when it is not available
% This part of code is useful when mass calculations are started on Unix/Linux machines. Usually, Matlab is
% run just from a command line and graphical output would yield an error, because graphical interface is not
% available. Therefore, if no output window is avaiable, this example is finished prematuraly. Also, the
% treatment is interrupted here, if no data are output from the treatment (this is the case for most of jobs,
% as they are not "remembering" results for all the image sequence).

if ~isstruct(pivData)|| ~usejava('jvm') || ~usejava('desktop') || ~feature('ShowFigureWindows')
    return;
end

%% Visualize the results
% Show a movie:

figure(2);
for kt = 1:pivData.Nt
    pivQuiver(pivData,'TimeSlice',kt,...   % choose data and time to show
        'V','clipLo',-1,'clipHi',3,...   % vertical velocity,
        'quiver','selectStat','valid');    % velocity vectors,
    drawnow;
    pause(0.04);
end

%% More details about distribution of the treatment between several jobs
% For more details, see description available in subroutine |pivManageJobs.m|.