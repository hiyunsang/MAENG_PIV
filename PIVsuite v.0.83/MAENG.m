clear;
pivPar = [];                                              % variable for settings
pivData = [];                                             % variable for storing results
imagePath = ['../Data/Test MAENG1'];  % folder with processed images
% NOTE: Use slash symbol (/) as path separator, both on Windows and Unix-based machines. In PIVsuite, never
% use backslash (\) or system-dependent path separator (filesep).

% get list of images in the folder and sort them
aux = dir([imagePath, '/', '*jpg.']);                 
for kk = 1:numel(aux), fileList{kk} = [imagePath, '/', aux(kk).name]; end   %#ok<SAGROW>
fileList = sort(fileList);

% Define image pairs
pivPar.seqPairInterval = 1;     % all image pairs will be processed in this example
pivPar.seqSeqDiff = 1;          % the second image in each pair is one frame after the first image
[im1,im2] = pivCreateImageSequence(fileList,pivPar);

%% Settings for processing the first image pair
% These settings will be used only for processing of the first image pair:

pivParInit.iaSizeX = [16 12 8 6 4];      % interrogation area size for five passes
pivParInit.iaStepX = [12 8 6 4 3];      % grid spacing for five passes
pivParInit.qvPair = {...                    % define plot shown between iterations
    'Umag','clipHi',3,...                                 % plot displacement magnitude, clip to 3 px      
    'quiver','selectStat','valid','linespec','-k',...     % show valid vectors in black
    'quiver','selectStat','replaced','linespec','-w'};    % show replaced vectors in white
[pivParInit, pivData] = pivParams([], pivParInit, 'defaults');

% pivParInit = pivParams([],pivParInit,'defaults');   % set defaults as if treating single image pair

%% Settings for processing subsequent image pairs
% Subsequent image pairs will be trated with these settings:

pivPar.iaSizeX = [16 8];                 % IA size; carry only two iterations for subsequent image pairs
pivPar.iaStepX = [8 4];                 % grid spacing 
pivPar.anVelocityEst = 'previousSmooth';  % use smoothed velocity from previous image pair as velocity 
                                          % estimate for image deformation
pivPar.anOnDrive = true;                  % files with results will be stored in an output folder
pivPar.anTargetPath = [imagePath,'/pivOut'];
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
figure(1);
% Set all other parameters to defaults:

[pivPar, pivData] = pivParams(pivData,pivPar,'defaultsSeq');
            
%% Running the analysis
% For processing a sequence of image pairs, execute command |pivAnalyeImageSequence|. Note that two setting
% variables are used: |pivPar|, which contains settings for all image pairs, and |pivParInit|, which defines
% how the first image pair is treated. Using settings above, the velocity field obtained in the first image
% pair is used for initialization of PIV analysis of the second pair.
%
% Treatment takes about 4 minutes (on my notebook made in 2013). Nevertheless, you can interrupt the treatment
% (Ctrl-C) and restart it; processing will continue by treating the first untreated image pair. Once all image
% pairs are treated, the PIVsuite only loads results of the treatment from files.

[pivData] = pivAnalyzeImageSequence(im1,im2,pivData,pivPar,pivParInit);

%% Visualize the results
% Show a movie:

figure(2);
for kr = 1:3                                   % repeat movie three times
    for kt = 1:pivData.Nt
        pivQuiver(pivData,'TimeSlice',kt,...   % choose data and time to show
            'V','clipLo',-1,'clipHi',3,...   % vertical velocity, 
            'quiver','selectStat','valid');    % velocity vectors, 
        drawnow;
        pause(0.04);
    end
end

%%
% Show the vertical profile of velocity RMS (sqrt(v'^2), averaged over X and time). (This is an example only;
% there are too few independent image pairs in this example to lead to reasonable statistics.)

Vrms = zeros(size(pivData.Y,1),1);
for ky = 1:numel(Vrms)
    Vrms(ky) = std(reshape(pivData.V(ky,:,:),pivData.Nt*pivData.Nx,1));
end
figure(3);
plot(Vrms,pivData.Y(:,1,1),'-b.');
title('Vertical evolution of velocity rms');
xlabel('V_{rms} (px)');
ylabel('Y (px)');
set(gca,'YDir','reverse');

%% 변형률 텐서 계산 

% 2) 변위 그리드 
Ugrid = pivData.U;    % [ny×nx] 크기 double
Vgrid = pivData.V;    % [ny×nx] 크기 double


% 3) 격자 간격(dx, dy) 설정
% uniform grid 라면 아래처럼 평균 간격을 써도 되고,
dx = pivData.Nx;   % x방향 간격
dy = pivData.Ny;   % y방향 간격


% 4) displacement gradient 계산
% [∂()/∂y, ∂()/∂x] 순서 주의
[dU_dy, dU_dx] = gradient(Ugrid, dy, dx);
[dV_dy, dV_dx] = gradient(Vgrid, dy, dx);

% 5) 작은 변형률 텐서 성분
eps_xx = dU_dx;                           
eps_yy = dV_dy;                           
eps_xy = 0.5*(dU_dy + dV_dx);             

% 6) (선택) 변형률 속도
 dt = 0.1;
 eps_rate_xx = eps_xx / dt;
 eps_rate_xy = eps_xy / dt;
 eps_rate_yy = eps_yy /dt;
% …

% 7) 유효 변형률
eps_eff = sqrt((2/3)*(eps_xx.^2+eps_yy.^2+2*eps_xy.^2));

eps_eff_rate = eps_eff/ dt; 


% 8) 시각화
figure;
subplot(2,2,1); imagesc(eps_xx); title('ε_{xx}');   axis image; colorbar;
subplot(2,2,2); imagesc(eps_yy); title('ε_{yy}');   axis image; colorbar;
subplot(2,2,3); imagesc(eps_xy); title('ε_{xy}');   axis image; colorbar;
subplot(2,2,4); imagesc(eps_eff); title('ε_{eff}'); axis image; colorbar;
sgtitle('PIV 변형률');
