%% MAENG_PAIR - 마스크 적용 이미지 페어(2장) PIV 분석
% 시퀀스 전체가 아니라 선택한 두 프레임만 빠르게 상호상관 분석합니다.
% 폴더와 프레임 번호(frameA/frameB)만 지정하면 나머지는 자동입니다.
% 분석 후 후처리는 postprocess 폴더의 MAENG_* 함수들을 사용하세요.

clear;
pivPar = [];      % PIV 분석 설정을 저장할 구조체 초기화
pivData = [];     % 분석 결과를 저장할 구조체 초기화

% 경로 등록: core(PIVsuite 엔진) + postprocess(MAENG 후처리)
thisDir = fileparts(mfilename('fullpath'));
addpath(fullfile(thisDir,'core'), fullfile(thisDir,'postprocess'));

%% 1. 이미지 · 마스크 경로 및 프레임 선택
% 데이터 폴더는 스크립트 위치 기준 절대경로로 고정 (MATLAB 현재 폴더와 무관하게 동작)
dataRoot  = strrep(fullfile(fileparts(thisDir), 'Data', '0602_400_27999_29034'), '\', '/');
maskPath  = [dataRoot, '/mask.bmp'];   % 마스크 이미지 경로
imagePath = dataRoot;                  % PIV 원본 이미지 폴더

frameA = 1;       % ★ 비교할 첫 번째 프레임 번호
frameB = 2;       % ★ 비교할 두 번째 프레임 번호 (보통 frameA+1)

% 폴더 내 .tif 이미지 목록을 프레임 순서대로 정렬
aux = dir([imagePath,'/*.tif']);
fileList = cell(1, numel(aux));
for kk = 1:numel(aux)
    fileList{kk} = [imagePath,'/', aux(kk).name];
end
fileList = sort(fileList);

if frameB > numel(fileList)
    error('frameB(%d)가 이미지 개수(%d)를 초과합니다.', frameB, numel(fileList));
end
im1 = fileList{frameA};
im2 = fileList{frameB};
fprintf('페어 분석: Frame %d (%s)  vs  Frame %d (%s)\n', ...
        frameA, aux(frameA).name, frameB, aux(frameB).name);

%% 2. 마스크 적용
% 파일 경로(문자열)를 그대로 전달하면 PIVsuite 내부에서 이진화 마스킹을 수행합니다.
pivPar.imMask1 = maskPath;
pivPar.imMask2 = maskPath;

%% 3. PIV 파라미터 (MAENG_SEQ와 동일한 다중 pass 구성)
pivPar.iaSizeX = [32 16 8];    % 각 pass의 IA(조사창) 크기
pivPar.iaStepX = [12 8 4];     % 공간 분해능(격자 간격)

% [안정성 확보] 마스킹된 빈 공간을 억지로 보간하려다 발생하는
% inpaint_nans (Rank deficient) 에러를 방지하기 위해 대체(Replacement) 기능을 끕니다.
pivPar.rpMethod = 'none';

% 벡터 검증 (Westerweel median test 기반)
pivPar.vlMinCC  = 0.3;         % 정규화 상호상관이 중앙값의 0.3 미만이면 기각
pivPar.vlPasses = [1 1 2];     % pass별 검증 횟수
pivPar.vlDist   = 3;           % 이웃 통계 범위 (3 = 7x7 이웃)
pivPar.vlTresh  = 2;           % 중앙값 검정 임계값
pivPar.vlEps    = 0.08;        % 허용 오차

% 속도장 스무딩
pivPar.smMethod = 'smoothn';   % 'none' | 'Gauss' | 'smoothn'
pivPar.smSigma  = 0.1;         % 클수록 부드러움 (NaN = 자동)

% 계산 중간 과정 모니터링 플롯
pivPar.qvPair = {...
    'Umag','clipHi',3,...
    'quiver','selectStat','valid','linespec','-k',...
    'quiver','selectStat','replaced','linespec','-w'};

% 누락된 파라미터를 페어 분석용 기본값으로 자동 보완
[pivPar, pivData] = pivParams(pivData, pivPar, 'defaults');

%% 4. PIV 분석 실행
fprintf('PIV 페어 분석을 시작합니다...\n');
figure(1);
[pivData] = pivAnalyzeImagePair(im1, im2, pivData, pivPar);

% 후처리 함수들이 배경 이미지를 찾을 수 있도록 파일 정보 기록
pivData.imFilename1 = im1;
pivData.imFilename2 = im2;
pivData.imagePath   = imagePath;

%% 5. 결과 저장
outDir = [imagePath,'/pivOut'];
if ~exist(outDir, 'dir'), mkdir(outDir); end
outFile = sprintf('%s/pivPair_%04d_%04d.mat', outDir, frameA, frameB);
save(outFile, 'pivData');
fprintf('결과 저장: %s\n', outFile);

%% 6. 결과 시각화 — 속도 크기 + 유효 벡터
colorMin = 0;      % 컬러바 최솟값
colorMax = 2.0;    % 컬러바 최댓값 (데이터 유속에 맞게 조절)

figure(2);
pivQuiver(pivData, ...
    'Umag', 'clipLo', colorMin, 'clipHi', colorMax, ...
    'quiver', 'selectStat', 'valid');
colorbar;
caxis([colorMin, colorMax]);   % R2022a 이상은 clim([colorMin, colorMax]);
title(sprintf('Velocity magnitude (Frame %d \\rightarrow %d)', frameA, frameB), 'FontSize', 12);
xlabel('position X (px)');
ylabel('position Y (px)');

%% 7. 품질 확인 — 상호상관 피크 / 피크 검출성(SNR)
figure(3);
pivQuiver(pivData, 'ccPeak', 'clipLo', 0.3, 'clipHi', 1);
colorbar;
title('Cross-correlation peak (a.u.)');
xlabel('position X (px)'); ylabel('position Y (px)');

figure(4);
pivQuiver(pivData, 'ccDetect', 'clipLo', 1.3, 'clipHi', 3);
colorbar;
title('Peak detectability — SNR > 1.5 = valid (Keane & Adrian)');
xlabel('position X (px)'); ylabel('position Y (px)');

%% 통계 요약
% (참고: validN 필드는 PIVsuite 문서에는 있으나 실제로는 채워지지 않아 직접 계산)
nValid = nnz(~isnan(pivData.U(:)));
fprintf('\n===== 페어 분석 요약 =====\n');
fprintf('격자: %d x %d\n', pivData.Nx, pivData.Ny);
fprintf('유효 벡터: %d개 / 무효(spurious) 벡터: %d개\n', nValid, pivData.spuriousN);
fprintf('평균 변위: U = %.3f px, V = %.3f px\n', ...
        mean(pivData.U(:),'omitnan'), mean(pivData.V(:),'omitnan'));
