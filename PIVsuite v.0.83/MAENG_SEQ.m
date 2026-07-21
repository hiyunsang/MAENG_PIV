%% MAENG_SEQ - 마스크 적용 이미지 시퀀스 PIV 분석 (데이터 저장/불러오기 기능 포함)
% 마스크 파일 경로를 직접 입력하는 가장 안정적인 방식의 시퀀스 파이프라인입니다.
% 분석 후 후처리는 postprocess 폴더의 MAENG_* 함수들을 사용하세요.
%   (예: MAENG_EffStrain, MAENG_StrainmapFwd, MAENG_VisualizePairFromSequence ...)

clear;
pivPar = [];      % PIV 분석 설정을 저장할 구조체 초기화
pivData = [];     % 분석 결과를 저장할 구조체 초기화

% 경로 등록: core(PIVsuite 엔진) + postprocess(MAENG 후처리)
thisDir = fileparts(mfilename('fullpath'));
addpath(fullfile(thisDir,'core'), fullfile(thisDir,'postprocess'));

%% 1. 이미지 및 마스크 경로 설정
% 데이터 폴더는 스크립트 위치 기준 절대경로로 고정 (MATLAB 현재 폴더와 무관하게 동작)
dataRoot  = strrep(fullfile(fileparts(thisDir), 'Data', 'T2_T3'), '\', '/');
USE_MASK  = true;                      % ★ 마스크 on/off (false면 마스크 없이 전체 영역 분석)
maskPath  = [dataRoot, '/mask.bmp'];   % 마스크 이미지 경로 (USE_MASK=false면 무시됨)
imagePath = dataRoot;                  % PIV 원본 이미지 경로

% 폴더 내의 .tif 확장자를 가진 모든 이미지 목록을 불러옵니다.
aux = dir([imagePath,'/*.tif']);
fileList = cell(1, numel(aux));
for kk = 1:numel(aux)
    fileList{kk} = [imagePath,'/', aux(kk).name];  
end
fileList = sort(fileList); % 프레임 순서에 맞게 정렬

%% 2. 마스크 적용 (USE_MASK=false면 건너뜀)
% 이미지를 imread로 불러오지 않고, 파일 경로(문자열) 자체를 파라미터로 넘깁니다.
% PIVsuite 내부에서 자동으로 이미지를 읽고 적절한 이진화 마스킹을 수행합니다.
if USE_MASK
    pivPar.imMask1 = maskPath;
    pivPar.imMask2 = maskPath;
else
    fprintf('>> 마스크 OFF — 전체 영역을 분석합니다.\n');
end

%% 3. 시퀀스 파라미터 및 데이터 저장(Save/Load) 설정
pivPar.seqPairInterval = 1;
pivPar.seqDiff = 1;             % 페어 내 프레임 간격 (1-2, 2-3 ...)
[im1,im2] = pivCreateImageSequence(fileList,pivPar);

pivPar.iaSizeX = [48 24 12];   % 4번의 pass에 대한 IA 크기
pivPar.iaStepX = [24 12 6];     % 공간 분해능(해상도)

% -------------------------------------------------------------------------
% [데이터 저장 및 불러오기 설정]
% 이미 계산된 데이터를 저장하고, 다음 실행 시 자동으로 불러오도록 설정합니다.
pivPar.anOnDrive = true;                  % 파일 저장 기능 활성화
pivPar.anTargetPath = [imagePath,'/pivOut']; % 결과 파일이 저장될 폴더 경로 설정
pivPar.anForceProcessing = false;         % false: 파일이 존재하면 재계산 없이 불러옴, true: 덮어쓰고 재계산
% -------------------------------------------------------------------------

% -------------------------------------------------------------------------
% [안정성 확보] 마스크 사용 시: 마스킹된 빈 공간을 억지로 보간(Interpolate)하려다
% 발생하는 inpaint_nans (Rank deficient) 에러를 방지하기 위해 대체 기능을 끕니다.
% 마스크 미사용 시: 엔진 기본값('inpaint')을 그대로 써서 불량 벡터를 대체합니다.
if USE_MASK
    pivPar.rpMethod = 'none';
end
% -------------------------------------------------------------------------

pivPar.qvPair = {...                 % 계산 중간 과정을 모니터링하기 위한 플롯 설정
    'Umag','clipHi',3,...                                 
    'quiver','selectStat','valid','linespec','-k','qScale',3,...     
    'quiver','selectStat','replaced','linespec','-w','qScale',3};    

% 누락된 파라미터들을 시퀀스 분석용 기본값('defaultsSeq')으로 자동 보완
[pivPar, pivData] = pivParams(pivData,pivPar,'defaultsSeq');
figure(1);

%% 4. PIV 분석 실행
% 처음 실행 시에는 데이터를 계산하여 폴더에 저장하며, 
% 두 번째 실행부터는 "Reading results from result file..." 메시지와 함께 즉시 데이터를 로드합니다.
fprintf('PIV 시퀀스 분석을 시작합니다...\n');
[pivData] = pivAnalyzeImageSequence(im1,im2,pivData,pivPar);

%% 4.5. PIV 품질 데이터 사전 추출 (이후 모든 품질 시각화 섹션의 공통 입력)
% -------------------------------------------------------------------------
% 섹션 5의 애니메이션이 길어 도중 중단되는 경우에도, 품질 분석에 필요한
% 변수들이 이미 워크스페이스에 만들어져 있도록 여기서 한 번에 준비합니다.
% -------------------------------------------------------------------------
ccPeakAll  = pivData.ccPeak;                   % 1차 피크 (ny x nx x Nt)
ccPeak2All = pivData.ccPeakSecondary;          % 2차 피크 (ny x nx x Nt)

% SNR(=Detectability) 계산. 분모가 NaN인 위치는 ccPeak로 대체하여 SNR=1로 처리.
auxNaN = isnan(ccPeak2All);
ccPeak2All(auxNaN) = ccPeakAll(auxNaN);
snrAll = ccPeakAll ./ ccPeak2All;              % (ny x nx x Nt)

Nt = pivData.Nt;                               % 프레임 수
Xax = pivData.X(1,:);                          % x축 좌표 벡터
Yax = pivData.Y(:,1);                          % y축 좌표 벡터
fprintf('PIV 품질 데이터 준비 완료 (Nt = %d frames).\n', Nt);

%% 5. 결과 시각화
% -------------------------------------------------------------------------
% [컬러바(Colorbar) 스케일 설정]
% 우측에 표시되는 컬러바의 범위를 설정합니다. 
% 이제 속도의 크기(절댓값)를 보므로 최솟값은 0으로 설정하는 것이 좋습니다.
colorMin = 0;     % 컬러바 최솟값 (절댓값이므로 0)
colorMax = 2.0;   % 컬러바 최댓값 (데이터 유속에 맞게 적절히 조절하세요)
% -------------------------------------------------------------------------

figure(2);
% 애니메이션을 1회만 재생합니다.
for kt = 1:pivData.Nt
    % 'Umag' 옵션을 사용하여 U와 V의 벡터합(속도 크기)을 배경 색상으로 표현합니다.
    % 'quiver' 옵션에서 subtractV를 제거하여 실제 유동 방향 화살표를 보여줍니다.
    pivQuiver(pivData,'TimeSlice',kt,...   
        'Umag', 'clipLo', colorMin, 'clipHi', colorMax,... % 속도 크기(Magnitude) 렌더링 및 범위 제한
        'quiver','selectStat','valid','qScale',3);                    % 유효한(valid) 벡터 화살표만 출력
    
    % 컬러바를 활성화하고 설정한 범위로 디스플레이 스케일을 단단히 고정합니다.
    colorbar; 
    caxis([colorMin, colorMax]); % 참고: 매트랩 R2022a 이상 버전에서는 clim([colorMin, colorMax]); 사용
    
    title(sprintf('Frame %d / %d (Velocity Magnitude)', kt, pivData.Nt), 'FontSize', 12);
    drawnow;
    pause(0.01);
end
%% 7. PIV 품질 검증: SNR 공간 맵 + 프레임별 SNR 추이 (논문 Figure - Option B)
% -------------------------------------------------------------------------
% 한 장의 논문용 Figure에 두 관점의 SNR 품질 지표를 담습니다.
%   (a) 시간 평균 SNR 공간 맵    → "어디에서" 신뢰도가 낮/높은지
%   (b) 프레임별 SNR 통계 추이   → "언제" 신뢰도가 흔들리는지
% Keane & Adrian (1990) 기준: SNR > 1.5 이면 valid vector.
% -------------------------------------------------------------------------
fprintf('\n[Publication-quality] SNR quality figure 생성...\n');

% --- 7-0. 안전장치
if ~exist('ccPeakAll','var')
    ccPeakAll = pivData.ccPeak;
    Xax = pivData.X(1,:);  Yax = pivData.Y(:,1);
    Nt  = pivData.Nt;
end

% --- 7-1. SNR 계산 (분모 안전화)
cc2safe = pivData.ccPeakSecondary;
cc2safe(isnan(cc2safe) | cc2safe < 1e-3) = 1e-3;
snrAll = ccPeakAll ./ cc2safe;
snrAll(snrAll < 0) = 0;

% --- 7-2. 시간 평균 (공간 맵용) + 마스크 보존
snrMean = mean(snrAll, 3, 'omitnan');
nanMask = all(isnan(ccPeakAll), 3);

% --- 7-3. 공간 스무딩
snrMeanS = smoothn(snrMean, 1.5);
snrMeanS(nanMask) = NaN;

% --- 7-4. 프레임별 SNR 통계 (시간축용)
snrStat = zeros(Nt, 2);   % [median, mean]
for kt = 1:Nt
    sn = snrAll(:,:,kt);
    snrStat(kt,1) = median(sn(:), 'omitnan');
    snrStat(kt,2) = mean(  sn(:), 'omitnan');
end
movWin = max(3, round(Nt*0.05));
snrStatS = movmean(snrStat, movWin, 1, 'omitnan');

% --- 7-5. 컬러맵 (진청→틸→라이트 민트, 끝색 흰색 아님)
keyC = [0.020 0.140 0.290;  0.050 0.280 0.470;
        0.130 0.450 0.590;  0.310 0.610 0.670;
        0.500 0.760 0.760;  0.660 0.850 0.815;
        0.780 0.905 0.855];
ts = linspace(0,1,size(keyC,1)).';  tq = linspace(0,1,256).';
qcmap = [interp1(ts,keyC(:,1),tq), interp1(ts,keyC(:,2),tq), interp1(ts,keyC(:,3),tq)];

% --- 7-6. SNR 컬러 범위 (데이터 분포 anchor)
vSNR = snrMeanS(~isnan(snrMeanS));
snrRange = [prctile(vSNR, 1), prctile(vSNR, 99)];
if diff(snrRange) < 0.5
    snrRange = mean(snrRange) + [-0.5, 0.5];
end

% --- 7-7. Figure (두 단 폭 ≈ 18 cm)
figure(3); clf;
set(gcf, 'Color','w', 'Units','centimeters', 'Position',[3 3 18 7.5]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

% ------------------ (a) 시간 평균 SNR 공간 맵 ------------------
ax1 = nexttile;
imagesc(Xax, Yax, snrMeanS, snrRange);
axis equal tight;
set(ax1,'YDir','reverse','Color',[0.85 0.85 0.85], ...
    'FontName','Arial','FontSize',10,'LineWidth',0.8,'TickDir','out','Box','on');
colormap(ax1, qcmap);
cb1 = colorbar(ax1); cb1.Label.String = 'SNR'; cb1.LineWidth = 0.8;
% 눈금: 데이터 범위 안의 표준 임계값만 자동 선택
cand = [1 1.5 2 5 10 15 20];
ticksIn = cand(cand >= snrRange(1) & cand <= snrRange(2));
cb1.Ticks = unique([snrRange(1), ticksIn, snrRange(2)]);
lbls = arrayfun(@(v) sprintf('%.2f', v), cb1.Ticks, 'UniformOutput', false);
for kk = 1:numel(cb1.Ticks)
    switch cb1.Ticks(kk)
        case 1.5, lbls{kk} = '1.5 (K&A)';
        case 2,   lbls{kk} = '2 (Good)';
        case 5,   lbls{kk} = '5 (Excellent)';
        case 10,  lbls{kk} = '10';
        case 20,  lbls{kk} = '20';
    end
end
cb1.TickLabels = lbls;
title(ax1,'(a) Spatial distribution of time-averaged SNR', ...
      'FontWeight','normal','FontSize',11);
xlabel(ax1,'x [px]'); ylabel(ax1,'y [px]');

% ------------------ (b) 프레임별 SNR 추이 ------------------
ax2 = nexttile; hold(ax2,'on'); grid(ax2,'on'); box(ax2,'on');
frames = 1:Nt;

% 원본(median)은 옅게, 스무딩된 곡선은 진하게
plot(ax2, frames, snrStat(:,1),   '-', 'Color',[0.75 0.80 0.85], 'LineWidth', 0.8);
hMed = plot(ax2, frames, snrStatS(:,1), '-', 'Color',[0.10 0.30 0.55], 'LineWidth', 2.0);
hAvg = plot(ax2, frames, snrStatS(:,2), '-', 'Color',[0.65 0.20 0.25], 'LineWidth', 2.0);

% Keane & Adrian 임계선
hThr = plot(ax2, [1 Nt], [1.5 1.5], '--', 'Color',[0.3 0.3 0.3], 'LineWidth', 1.0);
text(ax2, Nt*0.98, 1.55, ' SNR = 1.5 (Keane & Adrian, 1990)', ...
     'Color',[0.3 0.3 0.3], 'FontSize',9, 'HorizontalAlignment','right');

set(ax2, 'FontName','Arial','FontSize',10,'LineWidth',0.8,'TickDir','out');
xlabel(ax2,'Frame index'); ylabel(ax2,'SNR');
xlim(ax2, [1 Nt]);
% y축 상한: 데이터 최대의 1.1배 (임계선 1.5는 항상 보이도록 하한은 1.0)
ymax = max([snrStat(:); 2.0]) * 1.05;
ylim(ax2, [1.0, ymax]);
legend(ax2, [hMed, hAvg, hThr], ...
       {'median (smoothed)','mean (smoothed)','K&A threshold'}, ...
       'Location','best','FontSize',9,'Box','off');
title(ax2,'(b) Temporal evolution of frame-averaged SNR', ...
      'FontWeight','normal','FontSize',11);

% --- 7-8. 진단 + 저장
validRatio = sum(snrAll(:) > 1.5, 'omitnan') / sum(~isnan(snrAll(:))) * 100;
fprintf('  SNR spatial : median=%.2f, min=%.2f, max=%.2f\n', ...
        median(vSNR), min(vSNR), max(vSNR));
fprintf('  SNR temporal: frame-median range = [%.2f, %.2f]\n', ...
        min(snrStat(:,1)), max(snrStat(:,1)));
fprintf('  Valid vector yield (SNR > 1.5): %.2f %%\n', validRatio);
exportgraphics(gcf,'fig_piv_quality_SNR.png','Resolution',600);
exportgraphics(gcf,'fig_piv_quality_SNR.pdf','ContentType','vector');
%% 9. 절삭속도 검증 (직교절삭 / Orthogonal Cutting)
% -------------------------------------------------------------------------
% 우측에 툴, 좌측 하단에 공작물이 있는 직교절삭 구성입니다.
% 공작물은 강체처럼 x축 방향 성분만 가지므로, 해당 ROI 내 |U|의 통계를
% 그대로 절삭속도로 해석합니다.
%
% [사용법]
%   - 가장 간단: ROI 자동(좌측 1/2 × 하단 1/2), 단위는 px/frame
%       MAENG_CuttingSpeedAnalyze(pivData);
%
%   - ROI 직접 지정 (px):  [xMin xMax yMin yMax]
%       MAENG_CuttingSpeedAnalyze(pivData, 'roi', [0 300  400 600]);
%
%   - 실측 단위(m/min)로 변환: pixelSize(mm/px), dt(s/frame) 같이 지정
%       MAENG_CuttingSpeedAnalyze(pivData, ...
%           'roi', [0 300 400 600], 'pixelSize', 0.01, 'dt', 1/5000);
%
%   - ROI를 첫 프레임 위에 시각화하며 확인
%       MAENG_CuttingSpeedAnalyze(pivData, 'show', true);
%
% [반환값을 받고 싶다면]
%   cutStat = MAENG_CuttingSpeedAnalyze(pivData);
%   -> cutStat.maxSpeed / .minSpeed / .meanSpeed
%      .meanFirst3 / .meanLast3 / .perFrameMean / .unit / .roi
% -------------------------------------------------------------------------

% 이 줄을 풀면(주석 해제) 스크립트 마지막에 자동으로 한 번 출력됩니다.
cutStat = MAENG_CuttingSpeedAnalyze(pivData);  %#ok<NASGU>

% 필요 시 아래 줄을 풀어, 본인 광학계 보정값으로 m/min 단위 출력하세요.
% cutStat = MAENG_CuttingSpeedAnalyze(pivData, ...
%               'pixelSize', 0.01, ...   % mm/px (보정값으로 수정)
%               'dt',        1/5000, ... % s/frame (촬영 fps의 역수)
%               'roi',       []);        % 비워두면 자동 ROI 사용
