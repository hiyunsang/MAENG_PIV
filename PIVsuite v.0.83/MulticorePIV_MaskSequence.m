%% Multicore PIV — Masked Sequence (one-click parallel runner)
% (멀티코어 병렬 PIV · 마스킹 시퀀스 · 재생 한 번이면 끝)
% =========================================================================
% 사용법: 이 파일을 에디터에서 열고 [실행(Run, F5)] 한 번만 누르세요.
%   - GUI(현재 창)가 "코디네이터"가 되어 백그라운드 워커들을 자동으로 띄우고,
%     모든 쌍의 계산이 끝날 때까지 대기한 뒤, 전체 시퀀스를 조립하고
%     품질맵·절삭속도까지 시각화합니다. (2번째 실행 불필요)
%   - PIV 연산(IA 크기 / pass / 윈도우)은 단일 실행과 100% 동일하므로
%     결과물도 단일 실행과 동일합니다. (06b의 pass 축소 트릭은 쓰지 않음)
%
% 사전 준비 (딱 두 가지):
%   1) 'matlab' 명령이 시스템 PATH에 있어야 합니다(설치 시 보통 자동 등록).
%      안 되면 아래 SPAWN 부분의 'matlab'을 전체 경로로 바꾸세요. 예:
%      "C:\Program Files\MATLAB\R2023b\bin\matlab.exe"
%   2) 이 파일을 "저장"한 상태에서 실행하세요(저장 경로를 워커가 읽습니다).
% =========================================================================

clear;
nWorkers = 4;   % ★ 동시 계산 워커 수 = 본인 PC의 CPU 코어 수에 맞추세요 (예: 8코어면 8)

% ★ [워커가 띄울 MATLAB 실행파일] — 비워두면 현재 실행 중인 버전을 자동 사용.
%   "라이선스가 부여되지 않았습니다(다른 버전)" 에러가 나면, 라이선스가 있는
%   버전의 matlab.exe 전체 경로를 여기에 지정하세요. 예) R2024a:
%     matlabExe = 'C:\Program Files\MATLAB\R2024a\bin\matlab.exe';
matlabExe = '';   % 비우면 자동(matlabroot)

% ★ [오래된 작업관리 파일 자동 정리] true면 실행 직전 pivOut의 JobList.mat 과
%   lock_*.lck 만 삭제합니다 (이미지/결과 piv_*.mat 은 절대 안 건드림).
%   false면 아무것도 안 지우고, 오래된 락이 있으면 경고만 띄웁니다(수동 처리).
cleanStaleJobs = true;

%% ===== 공통 설정 (코디네이터·워커가 공유) =====
maskPath  = 'Data/0612/1-100-7882-9724/100mask.bmp';   % 마스크 이미지 경로
imagePath = 'Data/0612/1-100-7882-9724';               % PIV 원본 이미지 폴더

% 폴더 내 .tif 이미지 목록을 불러와 프레임 순서대로 정렬
aux = dir([imagePath,'/*.tif']);
fileList = cell(1, numel(aux));
for kk = 1:numel(aux)
    fileList{kk} = [imagePath,'/', aux(kk).name];
end
fileList = sort(fileList);

pivPar  = [];      % PIV 분석 설정
pivData = [];      % 분석 결과

% 마스크: 경로(문자열)를 그대로 전달하면 PIVsuite가 내부에서 이진화 처리
pivPar.imMask1 = maskPath;
pivPar.imMask2 = maskPath;

% 시퀀스 구성 (1-2, 2-3, 3-4 ...)
pivPar.seqPairInterval = 1;
pivPar.seqSeqDiff      = 1;
[im1,im2] = pivCreateImageSequence(fileList,pivPar);
im1Full = im1;  im2Full = im2;          % 전체 쌍 목록 보존 (조립 단계에서 사용)

% 처리 파라미터 (단일 실행과 동일하게 유지 — 결과 보존을 위해 pass 축소 금지)
pivPar.iaSizeX = [64 32 16];            % 3 pass IA 크기
pivPar.iaStepX = [32 16 8];             % 공간 분해능(그리드 간격)

% [디스크 캐시] 분배 처리의 필수 조건. 쌍별 결과를 파일로 저장하고,
% 이미 계산된 쌍은 재계산 없이 파일에서 읽습니다.
pivPar.anOnDrive         = true;
pivPar.anTargetPath      = [imagePath,'/pivOut'];   % 결과/락파일 저장 폴더
pivPar.anForceProcessing = false;                   % true로 두면 전부 재계산

% 마스킹된 빈 공간을 억지로 보간하다 나는 inpaint_nans 에러 방지
pivPar.rpMethod = 'none';

% [엄밀 재현이 필요하면 주석 해제] 프레임 간 의존을 끊어, 분할 여부와 무관하게
% 단일 실행과 비트 단위로 동일한 결과를 보장합니다(기본 'previous'와 미세하게
% 달라질 수 있으니 한 가지로 일관되게 사용하세요).
% pivPar.anVelocityEst = 'none';

% 계산 중 모니터링 플롯 설정(헤드리스 워커에서는 자동으로 무시됨)
pivPar.qvPair = {...
    'Umag','clipHi',3,...
    'quiver','selectStat','valid','linespec','-k',...
    'quiver','selectStat','replaced','linespec','-w'};

% 누락 파라미터를 시퀀스 기본값으로 자동 보완
[pivPar, pivData] = pivParams(pivData,pivPar,'defaultsSeq');

%% ===== 워커 모드: -batch로 떠서 자기 구간만 계산 후 종료 =====
% 백그라운드 MATLAB(-batch)에는 데스크톱이 없으므로 usejava('desktop')==false.
% 여기 진입한 인스턴스는 자기 몫만 계산해 디스크에 저장하고 스스로 종료합니다.
if ~usejava('desktop')
    pivPar.jmParallelJobs = nWorkers;
    [im1w,im2w,pivPar] = pivManageJobs(im1,im2,pivPar);   % 담당 구간만 배정받음
    pivAnalyzeImageSequence(im1w,im2w,pivData,pivPar);    % 계산 → piv_*.mat 저장
    return;                                               % 워커는 여기서 종료
end

%% ===== 코디네이터(GUI): 워커 실행 → 자동 대기 → 조립 → 시각화 =====
thisScript = [mfilename('fullpath'), '.m'];   % 현재 스크립트의 절대 경로
curDir     = pwd;                             % 워커가 동일한 상대경로를 쓰도록 cd 대상
nPairs     = numel(im1Full);

% --- 워커가 "조용히 실패"하지 않도록 두 가지를 명시적으로 넘깁니다 ---
% (a) MATLAB 실행파일: PATH에 의존하지 않고 버전을 직접 지정.
%     matlabExe가 비어 있으면 현재 실행 중인 버전(matlabroot)을 사용.
if isempty(matlabExe)
    if ispc, matlabExe = fullfile(matlabroot,'bin','matlab.exe');
    else,    matlabExe = fullfile(matlabroot,'bin','matlab');
    end
end
if ispc, mlExe = ['"', matlabExe, '"']; else, mlExe = matlabExe; end
% (b) PIVsuite 함수 폴더: 새로 뜬 워커는 path가 초기화되므로 addpath로 물려줌
pivDir = fileparts(which('pivCreateImageSequence'));   % 이미 path에 있는 함수로 폴더 역추적
if isempty(pivDir), pivDir = fileparts(thisScript); end % 안전장치
% 워커 부트스트랩: 함수경로 추가 → 작업폴더 이동 → 스크립트 실행
boot = sprintf('addpath(genpath(''%s''));cd(''%s'');run(''%s'')', pivDir, curDir, thisScript);

% --- (옵션) 이전 실행에서 남은 작업관리 파일 처리 ---
% 만료 안 된 오래된 lock_*.lck / JobList.mat 이 있으면 pivManageJobs가 그 작업을
% "이미 처리 중"으로 오인해 워커가 할 일을 못 받고 종료됩니다.
% cleanStaleJobs=true: 그 두 종류 파일만 삭제(결과 piv_*.mat 보존 → 이어하기 유지).
% cleanStaleJobs=false: 삭제하지 않고 경고만 표시.
if exist(pivPar.anTargetPath,'dir')
    stale = [dir(fullfile(pivPar.anTargetPath,'JobList.mat')); ...
             dir(fullfile(pivPar.anTargetPath,'lock_*.lck'))];
    if ~isempty(stale)
        if cleanStaleJobs
            for s = 1:numel(stale)
                delete(fullfile(pivPar.anTargetPath, stale(s).name));
            end
            fprintf('이전 작업관리 파일 %d개 정리(JobList/lock만, 결과는 보존).\n', numel(stale));
        else
            warning(['pivOut에 오래된 작업관리 파일 %d개가 있습니다. 워커가 멈출 수 ', ...
                     '있으니, %s 폴더의 JobList.mat / lock_*.lck 를 직접 지우거나 ', ...
                     'cleanStaleJobs=true 로 두세요.'], numel(stale), pivPar.anTargetPath);
        end
    end
end

% (1) 이미 완료된 쌍 수 확인 — 전부 캐시돼 있으면 워커를 띄우지 않고 바로 조립
nDone0 = numel(dir([pivPar.anTargetPath,'/piv_*.mat']));
if nDone0 < nPairs
    % 워커 nWorkers개를 백그라운드로 실행
    for w = 1:nWorkers
        % start 없이 & 로 백그라운드 실행 (start의 공백 경로/따옴표 처리 문제 회피).
        % 각 워커 출력을 로그로 남겨 문제 시 tempdir의 piv_worker_*.log 확인 가능.
        logw = fullfile(tempdir, sprintf('piv_worker_%d.log', w));
        spawnCmd = sprintf('%s -logfile "%s" -batch "%s" &', mlExe, logw, boot);
        system(spawnCmd);
    end
    fprintf('워커 %d개 실행 (MATLAB: %s). 계산이 끝날 때까지 기다립니다...\n', ...
            nWorkers, mlExe);
else
    fprintf('모든 결과가 이미 존재합니다(%d/%d). 워커 없이 바로 조립합니다.\n', ...
            nDone0, nPairs);
end

% (2) 완료 자동 대기: 결과 파일(piv_*.mat) 수가 전체 쌍 수에 도달할 때까지 폴링
t0 = tic;
while true
    nDone = numel(dir([pivPar.anTargetPath,'/piv_*.mat']));
    fprintf('  진행률: %d / %d 쌍  (%.0f s)\r', nDone, nPairs, toc(t0));
    if nDone >= nPairs, break; end
    if toc(t0) > 36000                      % 10시간 안전장치(필요 시 조정)
        warning('시간 초과 — 워커 상태(작업관리자의 matlab 프로세스)를 확인하세요.');
        break;
    end
    pause(3);
end
pause(3);                                   % 마지막 파일 저장 완료를 위한 여유
fprintf('\n전체 계산 완료. 디스크에서 시퀀스를 조립합니다...\n');

% (3) 전체 시퀀스 조립 (anForceProcessing=false → 재계산 없이 파일에서 읽기만 함)
pivParRead = pivPar;
pivParRead.anPairsOnly = false;
pivParRead.anStatsOnly = false;
if isfield(pivParRead,'jmLockFile'),   pivParRead = rmfield(pivParRead,'jmLockFile');   end
if isfield(pivParRead,'seqJobNumber'), pivParRead = rmfield(pivParRead,'seqJobNumber'); end
[pivData] = pivAnalyzeImageSequence(im1Full,im2Full,[],pivParRead);
fprintf('조립 완료 (Nt = %d). 시각화를 시작합니다.\n', pivData.Nt);
% 참고: 위 조립 단계에서 쌍마다 "Results found... Skipping" 메시지가 뜨는 것은
%       정상입니다. 재계산 없이 파일에서 읽는다는 뜻입니다.

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
        'quiver','selectStat','valid');                    % 유효한(valid) 벡터 화살표만 출력
    
    % 컬러바를 활성화하고 설정한 범위로 디스플레이 스케일을 단단히 고정합니다.
    colorbar; 
    caxis([colorMin, colorMax]); % 참고: 매트랩 R2022a 이상 버전에서는 clim([colorMin, colorMax]); 사용
    
    title(sprintf('Frame %d / %d (Velocity Magnitude)', kt, pivData.Nt), 'FontSize', 12);
    drawnow;
    pause(0.01);
end

%% 7. PIV 품질 검증: 시간평균 ccPeak / SNR 맵 (논문 출력 버전)
fprintf('\n[Publication-quality] ccPeak / SNR 품질 맵 생성...\n');

% --- 7-0. 안전장치
if ~exist('ccPeakAll','var')
    ccPeakAll = pivData.ccPeak;
    Xax = pivData.X(1,:);  Yax = pivData.Y(:,1);
end

% --- 7-1. SNR 계산: 분모 안전화 floor를 1e-3으로, 캡 없음
cc2safe = pivData.ccPeakSecondary;
cc2safe(isnan(cc2safe) | cc2safe < 1e-3) = 1e-3;
snrAll = ccPeakAll ./ cc2safe;
snrAll(snrAll < 0) = 0;

% --- 7-2. 시간 평균 + 마스크 보존
ccPeakMean = mean(ccPeakAll, 3, 'omitnan');
snrMean    = mean(snrAll,    3, 'omitnan');
nanMask    = all(isnan(ccPeakAll), 3);

% --- 7-3. 스무딩
ccPeakMeanS = smoothn(ccPeakMean, 1.5);  ccPeakMeanS(nanMask) = NaN;
snrMeanS    = smoothn(snrMean,    1.5);  snrMeanS(nanMask)    = NaN;

% --- 7-4. 컬러 범위: ccPeak는 임계값 anchor, SNR은 데이터 분포 anchor
cpRange  = [0.3, 1.0];                                  % ccPeak (고정)
vSNR     = snrMeanS(~isnan(snrMeanS));
snrRange = [prctile(vSNR, 1), prctile(vSNR, 99)];       % SNR (자동)
if diff(snrRange) < 0.5
    snrRange = mean(snrRange) + [-0.5, 0.5];            % 너무 좁으면 보정
end

% --- 7-5. 컬러맵: 진청→틸→라이트 민트 (끝색이 흰색에 너무 가깝지 않게)
keyC = [0.020 0.140 0.290;  0.050 0.280 0.470;
        0.130 0.450 0.590;  0.310 0.610 0.670;
        0.500 0.760 0.760;  0.660 0.850 0.815;
        0.780 0.905 0.855];
ts = linspace(0,1,size(keyC,1)).';  tq = linspace(0,1,256).';
qcmap = [interp1(ts,keyC(:,1),tq), interp1(ts,keyC(:,2),tq), interp1(ts,keyC(:,3),tq)];

% --- 7-6. Figure (논문 두 단 폭 ≈ 18 cm)
figure(3); clf;
set(gcf, 'Color','w', 'Units','centimeters', 'Position',[3 3 18 7.5]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

% (a) ccPeak
ax1 = nexttile;
imagesc(Xax, Yax, ccPeakMeanS, cpRange);
axis equal tight;
set(ax1,'YDir','reverse','Color',[0.85 0.85 0.85], ...
    'FontName','Arial','FontSize',10,'LineWidth',0.8,'TickDir','out','Box','on');
colormap(ax1, qcmap);
cb1 = colorbar(ax1); cb1.Label.String = 'ccPeak'; cb1.LineWidth = 0.8;
cb1.Ticks      = [0.3 0.5 0.7 1.0];
cb1.TickLabels = {'0.3','0.5 (Good)','0.7 (Excellent)','1.0'};
title(ax1,'(a) Time-averaged ccPeak','FontWeight','normal','FontSize',11);
xlabel(ax1,'x [px]'); ylabel(ax1,'y [px]');

% (b) SNR
ax2 = nexttile;
imagesc(Xax, Yax, snrMeanS, snrRange);
axis equal tight;
set(ax2,'YDir','reverse','Color',[0.85 0.85 0.85], ...
    'FontName','Arial','FontSize',10,'LineWidth',0.8,'TickDir','out','Box','on');
colormap(ax2, qcmap);
cb2 = colorbar(ax2); cb2.Label.String = 'SNR'; cb2.LineWidth = 0.8;
% SNR 눈금: 데이터 범위 안의 의미 있는 임계값만 자동 선택
candidates = [1 2 5 10 15 20];
ticksIn = candidates(candidates >= snrRange(1) & candidates <= snrRange(2));
cb2.Ticks = unique([snrRange(1), ticksIn, snrRange(2)]);
lbls = arrayfun(@(v) sprintf('%.2f', v), cb2.Ticks, 'UniformOutput', false);
for kk = 1:numel(cb2.Ticks)
    switch cb2.Ticks(kk)
        case 2,  lbls{kk} = '2 (Good)';
        case 5,  lbls{kk} = '5 (Excellent)';
        case 10, lbls{kk} = '10';
        case 20, lbls{kk} = '20';
    end
end
cb2.TickLabels = lbls;
title(ax2,'(b) Time-averaged SNR','FontWeight','normal','FontSize',11);
xlabel(ax2,'x [px]'); ylabel(ax2,'y [px]');

% --- 7-7. 진단 + 저장
fprintf('  ccPeak: median=%.3f, max=%.3f (color range fixed: [%.2f, %.2f])\n', ...
        median(ccPeakMeanS(~isnan(ccPeakMeanS))), max(ccPeakMeanS(:),[],'omitnan'), cpRange);
fprintf('  SNR   : median=%.3f, max=%.2f (color range auto: [%.2f, %.2f])\n', ...
        median(snrMeanS(~isnan(snrMeanS))), max(snrMeanS(:),[],'omitnan'), snrRange);
exportgraphics(gcf,'fig_piv_quality.png','Resolution',600);
exportgraphics(gcf,'fig_piv_quality.pdf','ContentType','vector');

%% 8. 프레임별 PIV 품질 추이 (시간축 통계)
% 시간에 따라 품질이 일정한지(특정 프레임만 망가지지 않았는지) 확인합니다.
ccPeakStat = zeros(Nt, 2);     % [median, mean]
snrStat    = zeros(Nt, 2);

for kt = 1:Nt
    cp = ccPeakAll(:,:,kt);
    sn = snrAll(:,:,kt);
    ccPeakStat(kt,1) = median(cp(:), 'omitnan');
    ccPeakStat(kt,2) = mean(  cp(:), 'omitnan');
    snrStat(kt,1)    = median(sn(:), 'omitnan');
    snrStat(kt,2)    = mean(  sn(:), 'omitnan');
end

% --- 시간축에 약한 이동평균 (가독성 향상)
movWin = max(3, round(Nt*0.05));        % 전체의 5% 또는 최소 3프레임
ccPeakStatS = movmean(ccPeakStat, movWin, 1, 'omitnan');
snrStatS    = movmean(snrStat,    movWin, 1, 'omitnan');

figure(4); clf;
set(gcf, 'Name', 'PIV Quality: per-frame statistics', 'Color', 'w');
frames = 1:Nt;

% (a) ccPeak 추이
subplot(2,1,1); hold on; grid on; box on;
plot(frames, ccPeakStat(:,1), 'Color',[0.75 0.75 1.0], 'LineWidth', 0.8);  % raw median
plot(frames, ccPeakStatS(:,1), '-b', 'LineWidth', 2.0);                    % smoothed median
plot(frames, ccPeakStatS(:,2), '-r', 'LineWidth', 2.0);                    % smoothed mean
plot([1 Nt], [0.5 0.5], '--k', 'LineWidth', 1.0);                          % Good threshold
plot([1 Nt], [0.3 0.3], '--', 'Color',[0.6 0.2 0.2], 'LineWidth', 1.0);    % Poor threshold
text(Nt, 0.51, ' Good > 0.5', 'Color','k', 'FontSize',9);
text(Nt, 0.31, ' Poor < 0.3', 'Color',[0.6 0.2 0.2], 'FontSize',9);
ylim([0 1]); xlim([1 Nt]);
xlabel('Frame index'); ylabel('ccPeak');
legend({'median (raw)','median (smoothed)','mean (smoothed)'}, 'Location','best');
title('Frame-wise ccPeak', 'FontSize', 12);

% (b) SNR 추이
subplot(2,1,2); hold on; grid on; box on;
plot(frames, snrStat(:,1), 'Color',[1.0 0.75 0.75], 'LineWidth', 0.8);
plot(frames, snrStatS(:,1), '-b', 'LineWidth', 2.0);
plot(frames, snrStatS(:,2), '-r', 'LineWidth', 2.0);
plot([1 Nt], [2.0 2.0], '--k', 'LineWidth', 1.0);
plot([1 Nt], [1.5 1.5], '--', 'Color',[0.6 0.2 0.2], 'LineWidth', 1.0);
text(Nt, 2.02, ' Good > 2.0', 'Color','k', 'FontSize',9);
text(Nt, 1.52, ' Marginal < 1.5', 'Color',[0.6 0.2 0.2], 'FontSize',9);
xlim([1 Nt]);
xlabel('Frame index'); ylabel('SNR');
legend({'median (raw)','median (smoothed)','mean (smoothed)'}, 'Location','best');
title('Frame-wise SNR (= ccPeak / ccPeakSecondary)', 'FontSize', 12);

% --- 콘솔에 요약 통계 출력
fprintf('\n=== PIV 품질 요약 ===\n');
fprintf('  ccPeak : 전체 평균 = %.3f , 중앙값 = %.3f\n', ...
        mean(ccPeakMean(:),'omitnan'), median(ccPeakMean(:),'omitnan'));
fprintf('  SNR    : 전체 평균 = %.3f , 중앙값 = %.3f\n', ...
        mean(snrMean(:),'omitnan'),    median(snrMean(:),'omitnan'));
fprintf('  → ccPeak > 0.5 그리고 SNR > 2.0 이면 PIV 결과가 양호합니다.\n');

%% 9. 절삭속도 검증 (직교절삭 / Orthogonal Cutting)
% -------------------------------------------------------------------------
% 우측에 툴, 좌측 하단에 공작물이 있는 직교절삭 구성입니다.
% 공작물은 강체처럼 x축 방향 성분만 가지므로, 해당 ROI 내 |U|의 통계를
% 그대로 절삭속도로 해석합니다.
%
% [사용법]
%   - 가장 간단: ROI 자동(좌측 1/2 × 하단 1/2), 단위는 px/frame
%       cuttingSpeedAnalyze(pivData);
%
%   - ROI 직접 지정 (px):  [xMin xMax yMin yMax]
%       cuttingSpeedAnalyze(pivData, 'roi', [0 300  400 600]);
%
%   - 실측 단위(m/min)로 변환: pixelSize(mm/px), dt(s/frame) 같이 지정
%       cuttingSpeedAnalyze(pivData, ...
%           'roi', [0 300 400 600], 'pixelSize', 0.01, 'dt', 1/5000);
%
%   - ROI를 첫 프레임 위에 시각화하며 확인
%       cuttingSpeedAnalyze(pivData, 'show', true);
%
% [반환값을 받고 싶다면]
%   cutStat = cuttingSpeedAnalyze(pivData);
%   -> cutStat.maxSpeed / .minSpeed / .meanSpeed
%      .meanFirst3 / .meanLast3 / .perFrameMean / .unit / .roi
% -------------------------------------------------------------------------

% 이 줄을 풀면(주석 해제) 스크립트 마지막에 자동으로 한 번 출력됩니다.
cutStat = cuttingSpeedAnalyze(pivData);  %#ok<NASGU>

% 필요 시 아래 줄을 풀어, 본인 광학계 보정값으로 m/min 단위 출력하세요.
% cutStat = cuttingSpeedAnalyze(pivData, ...
%               'pixelSize', 0.01, ...   % mm/px (보정값으로 수정)
%               'dt',        1/5000, ... % s/frame (촬영 fps의 역수)
%               'roi',       []);        % 비워두면 자동 ROI 사용