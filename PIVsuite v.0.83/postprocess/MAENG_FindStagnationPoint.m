function stagData = MAENG_FindStagnationPoint(pivData, varargin)
% MAENG_FindStagnationPoint - 직교절삭 PIV 결과에서 프레임별 정체점 검출 (v2)
%
% ★ 사용법 1: 그냥 재생 버튼 (▶/F5) 누르기 ★
%   아래 [기본 설정] 블록의 경로와 ROI를 조정한 뒤 재생 버튼을 누르면
%   저장된 PIV 결과(pivOut/...)를 자동으로 불러와 정체점 검출을 실행합니다.
%
% ★ 사용법 2: 다른 스크립트에서 함수로 호출 ★
%   stagData = MAENG_FindStagnationPoint(pivData, 'MaskImage', maskPath, ...
%                                     'ROI', [xmin xmax ymin ymax])
%
% =========================================================================
% [기본 설정] — 재생 버튼으로 실행할 때 사용되는 값들
% =========================================================================
DEFAULT_PIV_DIR    = '../Data/0507PIV3/pivOut';        % PIV 결과 폴더
DEFAULT_MASK_PATH  = '../Data/0507PIV3/0507PIV3.bmp';  % 마스크 이미지 경로
DEFAULT_ROI        = [290 460 300 440];                % 정체점 예상 영역
DEFAULT_BAND_WIDTH = 30;                                % 탐색 두께 [px]
DEFAULT_COLOR_RNG  = [0 2];                             % 배경 컬러 범위
DEFAULT_DEBUG      = true;                              % 첫 실행 시 true
% =========================================================================

% --- 인자가 없으면 (재생 버튼 모드): 디스크에서 자동 로드 후 자기 자신 재호출
if nargin == 0
    fprintf('\n[재생 버튼 모드] PIV 결과를 자동으로 불러옵니다...\n');
    fprintf('  폴더: %s\n', DEFAULT_PIV_DIR);

    % .mat 파일 후보 찾기
    cand = dir(fullfile(DEFAULT_PIV_DIR, '*.mat'));
    if isempty(cand)
        error(['PIV 결과 .mat 파일을 찾을 수 없습니다:\n  %s\n', ...
               '메인 PIV 스크립트를 먼저 실행하거나, 이 파일 상단의\n', ...
               'DEFAULT_PIV_DIR 경로를 확인하세요.'], DEFAULT_PIV_DIR);
    end
    % 가장 큰 .mat (보통 시퀀스 통합 결과가 가장 큼)
    [~, idx] = max([cand.bytes]);
    pivMat = fullfile(DEFAULT_PIV_DIR, cand(idx).name);
    fprintf('  로드: %s\n', cand(idx).name);

    S = load(pivMat);
    pivData = [];
    fn = fieldnames(S);
    for k = 1:numel(fn)
        v = S.(fn{k});
        if isstruct(v) && isfield(v,'X') && isfield(v,'U') && isfield(v,'V')
            pivData = v;
            fprintf('  → 구조체 "%s" 사용\n', fn{k});
            break;
        end
    end
    if isempty(pivData)
        error('.mat 안에서 PIV 데이터 구조체(X,U,V 필드)를 찾을 수 없습니다.');
    end

    % 마스크 파일 자동 탐색
    %   순서: 1) DEFAULT_MASK_PATH 그대로 존재하면 사용
    %         2) PIV 폴더 부모 디렉토리에서 .bmp 검색
    %         3) 못 찾으면 빈값 → 함수가 pivData NaN을 자동 fallback
    maskFound = '';
    if exist(DEFAULT_MASK_PATH, 'file') == 2
        maskFound = DEFAULT_MASK_PATH;
    else
        parentDir = fileparts(DEFAULT_PIV_DIR);   % pivOut의 부모
        bmpCand = dir(fullfile(parentDir, '*.bmp'));
        if ~isempty(bmpCand)
            maskFound = fullfile(parentDir, bmpCand(1).name);
            fprintf('  마스크 자동 검색: %s\n', maskFound);
        else
            fprintf('  마스크 파일 없음 → pivData의 NaN 패턴 사용\n');
        end
    end

    % 자기 자신을 함수로 재호출
    stagData = MAENG_FindStagnationPoint(pivData, ...
        'MaskImage',     maskFound, ...
        'ROI',           DEFAULT_ROI, ...
        'BandWidth',     DEFAULT_BAND_WIDTH, ...
        'ColorRange',    DEFAULT_COLOR_RNG, ...
        'SaveDir',       DEFAULT_PIV_DIR, ...
        'Debug',         DEFAULT_DEBUG, ...
        'ShowAnimation', true);
    return;
end
% MAENG_FindStagnationPoint - 직교절삭 PIV 결과에서 프레임별 정체점 검출 (v2)
%
% [핵심 알고리즘 v2]
%   ROI 박스 안에서 마스크 경계로부터 BandWidth 거리 이내의 유체 점들 중
%   "saddle score = mean(|V|, 5x5) - |V|(center)"가 최대인 위치를 정체점으로
%   검출합니다. 단순 |V|min이 아니라 "주변보다 작은 골" 형태를 찾으므로
%   PIV 노이즈와 마스크 경계 부근의 0속도 영역에 강인합니다.
%
% 사용법 (가장 단순):
%   stagData = MAENG_FindStagnationPoint(pivData, 'MaskImage', maskPath, ...
%                                     'ROI', [xmin xmax ymin ymax])
%
% 한 번 호출로 다음을 모두 수행:
%   1) ROI 안에서 saddle point 검출 (프레임별)
%   2) 좌표 시계열 콘솔 출력 + .mat 저장
%   3) 시간 평균 위치 ± 표준편차 출력
%   4) Figure: y/x 시간 추이 그래프
%   5) Figure: 각 프레임 위에 정체점 오버레이 애니메이션
%
% 입력:
%   pivData : pivAnalyzeImageSequence 출력 (또는 단일 페어)
%             - .X, .Y : (Ny x Nx) 격자
%             - .U, .V : (Ny x Nx) 또는 (Ny x Nx x Nt)
%
% 선택 입력 (Name-Value):
%   'MaskImage'    : 마스크 이미지 경로 또는 행렬 (1=유체, 0=mask)
%                    없으면 pivData.U의 NaN 위치를 mask로 간주
%   'ROI'          : [xmin xmax ymin ymax]  ★ 필수 권장 ★
%                    이 박스 안에서만 정체점을 찾습니다.
%                    영상에서 정체점이 있을 거라고 생각되는 영역을 박스로.
%   'BandWidth'    : 마스크 경계로부터 유체쪽으로 몇 px까지를 후보로 볼지
%                    (기본 25. BUE 반경 + 약간 여유. 너무 작으면 마스크 옆
%                    한 줄만 보고, 너무 크면 멀리 있는 0속도 영역도 잡힘)
%   'SmoothField'  : 속도장 공간 스무딩 가우시안 sigma [px] (기본 0 = off)
%   'SaveDir'      : 결과 저장 폴더 (기본 pivData.anTargetPath 또는 ./pivOut)
%   'ShowAnimation': 오버레이 애니메이션 표시 (기본 true)
%   'PauseSec'     : 애니메이션 프레임 간격 [s] (기본 0.02)
%   'ColorRange'   : 배경 Umag 컬러 범위 [lo hi] (기본 [0 2])
%   'Debug'        : true이면 ROI / 검색 영역 / 검출 위치를 한 그림에 표시
%   'Verbose'      : 진행 메시지 (기본 true)
%
% 출력 stagData:
%   .x, .y         : (Nt x 1) 프레임별 정체점 좌표
%   .Vmag          : (Nt x 1) 검출 지점의 |V| (작을수록 좋음)
%   .valid         : (Nt x 1) 검출 성공 여부
%   .meanX, .meanY : 평균 위치
%   .stdX,  .stdY  : 표준편차
%   .searchMask    : (Ny x Nx) 후보 점들의 격자 마스크 (디버그용)
%   .Nt            : 프레임 수

% --- 입력 파싱 -----------------------------------------------------------
p = inputParser;
addParameter(p, 'MaskImage',     [],      @(x) ischar(x) || isstring(x) || isnumeric(x) || islogical(x));
addParameter(p, 'ROI',           [],      @(x) isempty(x) || (isnumeric(x) && numel(x)==4));
addParameter(p, 'BandWidth',     25,      @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'SmoothField',   0,       @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'SaveDir',       '',      @(x) ischar(x) || isstring(x));
addParameter(p, 'ShowAnimation', true,    @islogical);
addParameter(p, 'PauseSec',      0.02,    @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'ColorRange',    [0 2],   @(x) isnumeric(x) && numel(x)==2);
addParameter(p, 'Debug',         false,   @islogical);
addParameter(p, 'Verbose',       true,    @islogical);
parse(p, varargin{:});
opt = p.Results;

% --- 데이터 차원 처리 ---------------------------------------------------
X = pivData.X;  Y = pivData.Y;
U = pivData.U;  V = pivData.V;
if ndims(U) == 2
    Nt = 1;
    U = reshape(U, [size(U,1), size(U,2), 1]);
    V = reshape(V, [size(V,1), size(V,2), 1]);
else
    Nt = size(U, 3);
end
if isfield(pivData, 'Nt') && ~isempty(pivData.Nt), Nt = pivData.Nt; end

if opt.Verbose
    fprintf('\n[MAENG_FindStagnationPoint v2] Nt = %d\n', Nt);
end

% --- 후보 검색 마스크 (격자 해상도) 만들기 -------------------------------
% 1) ROI 박스 안
% 2) 마스크 경계로부터 BandWidth 안쪽 (유체쪽)
% 3) 유효한(NaN 아닌) PIV 격자점
searchMask = local_buildSearchMask(X, Y, pivData, opt);

if sum(searchMask(:)) < 3
    error('MAENG_FindStagnationPoint:EmptySearch', ...
        '검색 영역이 비어 있습니다. ROI나 BandWidth를 조정하세요.');
end

if opt.Verbose
    fprintf('  검색 격자점 개수: %d (전체 %d 중)\n', ...
        sum(searchMask(:)), numel(searchMask));
end

% --- 디버그 시각화 (한 번만) --------------------------------------------
if opt.Debug
    local_plotDebug(X, Y, pivData, searchMask, opt);
end

% --- 결과 컨테이너 -------------------------------------------------------
stagData.x          = nan(Nt, 1);
stagData.y          = nan(Nt, 1);
stagData.Vmag       = nan(Nt, 1);
stagData.valid      = false(Nt, 1);
stagData.searchMask = searchMask;
stagData.Nt         = Nt;

% --- 프레임별 검출 -------------------------------------------------------
sigma = opt.SmoothField;
for kt = 1:Nt
    Uk = U(:,:,kt);
    Vk = V(:,:,kt);

    % 공간 스무딩 (선택)
    if sigma > 0
        Uk = local_gaussSmooth(Uk, sigma);
        Vk = local_gaussSmooth(Vk, sigma);
    end

    % 속도 크기
    Umag = sqrt(Uk.^2 + Vk.^2);

    % --- saddle 점수 계산 ---
    % 정체점 조건 강화:
    %  (a) |V|가 국소적으로 작음 (단순 min)
    %  (b) 주변에서 |V|가 빠르게 증가 (국소 minimum이고 골이 깊을수록 점수↑)
    %  (c) 발산성 흐름: 정체점에서 멀어지는 방향으로 속도 벡터가 향함
    %      (divergence > 0이거나, 주변 평균 |V|가 중심 |V|보다 충분히 큼)
    %
    % 점수 = mean(|V| in 5x5) - |V|(center)  → "깊이"
    [Ny, Nx] = size(Umag);
    kernSize = 5;
    halfK = floor(kernSize/2);
    meanUmag = local_localMean(Umag, halfK);     % NaN-safe 국소 평균
    saddleScore = meanUmag - Umag;                % 양수일수록 골(국소 최소)

    % 검색 영역만
    candidate = searchMask & ~isnan(saddleScore);
    if ~any(candidate(:)), continue; end

    % 최고 점수 위치 (가장 깊은 |V| 골)
    sVal = saddleScore;
    sVal(~candidate) = -Inf;
    [maxVal, ind] = max(sVal(:));
    if isinf(maxVal) || isnan(maxVal), continue; end

    [iy, ix] = ind2sub(size(sVal), ind);

    % 서브픽셀: 주변 3x3 saddleScore 가중치
    [xs, ys] = local_subpixelMax(X, Y, saddleScore, iy, ix);

    stagData.x(kt)     = xs;
    stagData.y(kt)     = ys;
    stagData.Vmag(kt)  = Umag(iy, ix);
    stagData.valid(kt) = true;
end

% --- 통계 (Octave 호환) -------------------------------------------------
xx = stagData.x(~isnan(stagData.x));
yy = stagData.y(~isnan(stagData.y));
if ~isempty(xx), stagData.meanX = mean(xx); else, stagData.meanX = NaN; end
if ~isempty(yy), stagData.meanY = mean(yy); else, stagData.meanY = NaN; end
if numel(xx) > 1, stagData.stdX = std(xx); else, stagData.stdX = NaN; end
if numel(yy) > 1, stagData.stdY = std(yy); else, stagData.stdY = NaN; end

% =========================================================================
% 출력 ①: 콘솔 표 + .mat 저장
% =========================================================================
if opt.Verbose
    fprintf('\n=== 정체점 좌표 시계열 (처음 10 프레임) ===\n');
    fprintf('  frame     x [px]      y [px]    |V|min\n');
    for kt = 1:min(10, Nt)
        fprintf('  %4d   %9.2f   %9.2f   %7.4f\n', ...
            kt, stagData.x(kt), stagData.y(kt), stagData.Vmag(kt));
    end
    if Nt > 10, fprintf('  ... (총 %d 프레임)\n', Nt); end
end

saveDir = char(opt.SaveDir);
if isempty(saveDir)
    if isfield(pivData, 'anTargetPath') && ~isempty(pivData.anTargetPath)
        saveDir = pivData.anTargetPath;
    else
        saveDir = fullfile(pwd, 'pivOut');
    end
end
if ~exist(saveDir, 'dir'), mkdir(saveDir); end
save(fullfile(saveDir, 'stagnationPoint.mat'), 'stagData');
if opt.Verbose
    fprintf('\n저장 → %s\n', fullfile(saveDir, 'stagnationPoint.mat'));
end

% =========================================================================
% 출력 ③: 통계 콘솔
% =========================================================================
if opt.Verbose
    fprintf('\n=== 통계 ===\n');
    fprintf('  검출 성공률: %d / %d (%.1f %%)\n', ...
        sum(stagData.valid), Nt, 100*sum(stagData.valid)/max(Nt,1));
    fprintf('  평균 위치  : x = %.2f ± %.2f px, y = %.2f ± %.2f px\n', ...
        stagData.meanX, stagData.stdX, stagData.meanY, stagData.stdY);
end

% =========================================================================
% 출력 ④: 시간 추이 그래프
% =========================================================================
if Nt >= 2
    figure('Name', 'Stagnation point: position vs frame', 'Color', 'w');
    frames = (1:Nt).';

    subplot(2,1,1); hold on; grid on; box on;
    plot(frames, stagData.y, '-o', 'Color',[0.2 0.4 0.8], ...
        'MarkerSize', 4, 'LineWidth', 1.2, 'MarkerFaceColor',[0.2 0.4 0.8]);
    local_hline(stagData.meanY,                 '--', 'k',          sprintf('mean = %.2f', stagData.meanY), Nt);
    local_hline(stagData.meanY+stagData.stdY,   ':',  [0.5 0.5 0.5], '', Nt);
    local_hline(stagData.meanY-stagData.stdY,   ':',  [0.5 0.5 0.5], '', Nt);
    xlabel('Frame index'); ylabel('y_{stag} [px]');
    title('Stagnation point height (y)', 'FontSize', 12);
    xlim([1 Nt]);

    subplot(2,1,2); hold on; grid on; box on;
    plot(frames, stagData.x, '-s', 'Color',[0.85 0.3 0.2], ...
        'MarkerSize', 4, 'LineWidth', 1.2, 'MarkerFaceColor',[0.85 0.3 0.2]);
    local_hline(stagData.meanX,                 '--', 'k',          sprintf('mean = %.2f', stagData.meanX), Nt);
    local_hline(stagData.meanX+stagData.stdX,   ':',  [0.5 0.5 0.5], '', Nt);
    local_hline(stagData.meanX-stagData.stdX,   ':',  [0.5 0.5 0.5], '', Nt);
    xlabel('Frame index'); ylabel('x_{stag} [px]');
    title('Stagnation point x', 'FontSize', 12);
    xlim([1 Nt]);
end

% =========================================================================
% 출력 ②: 오버레이 애니메이션
% =========================================================================
if opt.ShowAnimation
    figure('Name', 'Stagnation point overlay', 'Color', 'w');
    colorMin = opt.ColorRange(1);  colorMax = opt.ColorRange(2);
    hasPivQuiver = exist('pivQuiver', 'file') == 2;

    for kt = 1:Nt
        clf;
        if hasPivQuiver
            try
                pivQuiver(pivData, 'TimeSlice', kt, ...
                    'Umag', 'clipLo', colorMin, 'clipHi', colorMax, ...
                    'quiver', 'selectStat', 'valid');
            catch
                local_fallbackBg(X, Y, U(:,:,kt), V(:,:,kt), colorMin, colorMax);
            end
        else
            local_fallbackBg(X, Y, U(:,:,kt), V(:,:,kt), colorMin, colorMax);
        end
        hold on;

        % ROI 박스
        if ~isempty(opt.ROI)
            r = opt.ROI;
            plot([r(1) r(2) r(2) r(1) r(1)], [r(3) r(3) r(4) r(4) r(3)], ...
                '-', 'Color', [1 0.5 0], 'LineWidth', 1.5);
        end

        % 평균 위치 (희미한 +)
        if ~isnan(stagData.meanX)
            plot(stagData.meanX, stagData.meanY, '+', ...
                'Color',[1 1 1]*0.9, 'MarkerSize', 14, 'LineWidth', 1.2);
        end

        % 현재 프레임 정체점
        if stagData.valid(kt)
            plot(stagData.x(kt), stagData.y(kt), 'o', ...
                'MarkerSize', 12, 'LineWidth', 2.2, ...
                'MarkerEdgeColor', 'r', 'MarkerFaceColor', [1 1 0.4]);
            tag = '';
        else
            tag = ' [실패]';
        end

        colorbar;
        try, caxis([colorMin, colorMax]); catch, clim([colorMin, colorMax]); end
        title(sprintf('Frame %d / %d  —  stag @ (%.1f, %.1f) px%s', ...
            kt, Nt, stagData.x(kt), stagData.y(kt), tag), 'FontSize', 12);
        drawnow;
        if opt.PauseSec > 0, pause(opt.PauseSec); end
    end
end

if opt.Verbose, fprintf('\n[MAENG_FindStagnationPoint v2] 완료.\n'); end
end % function ---------------------------------------------------------


% =========================================================================
% 보조 1: 검색 마스크 만들기 (ROI + 마스크 경계 근방 + 유효 벡터)
% =========================================================================
function searchMask = local_buildSearchMask(X, Y, pivData, opt)
[Ny, Nx] = size(X);

% (a) ROI: 격자 좌표 기준
if isempty(opt.ROI)
    inROI = true(Ny, Nx);
else
    r = opt.ROI;
    inROI = (X >= r(1)) & (X <= r(2)) & (Y >= r(3)) & (Y <= r(4));
end

% (b) 유체 마스크 (PIV 격자상)
%     우선순위: 명시 MaskImage (있고 파일이 존재할 때) > pivData.U의 NaN 위치
fluidGrid = true(Ny, Nx);
useMaskFile = false;

if ~isempty(opt.MaskImage)
    if ischar(opt.MaskImage) || isstring(opt.MaskImage)
        if exist(char(opt.MaskImage), 'file') == 2
            useMaskFile = true;
            M = imread(char(opt.MaskImage));
        else
            warning('MAENG_FindStagnationPoint:MaskFileMissing', ...
                ['마스크 파일을 찾을 수 없어 pivData.U의 NaN 패턴을 ', ...
                 '마스크로 사용합니다:\n  %s'], char(opt.MaskImage));
        end
    else
        useMaskFile = true;
        M = opt.MaskImage;
    end
end

if useMaskFile
    if size(M,3) > 1, M = M(:,:,1); end
    maskPix = M > (max(M(:)) / 2);   % 1 = 유체

    % 픽셀 마스크를 PIV 격자상으로 nearest-interp
    [Hm, Wm] = size(maskPix);
    [Xpx, Ypx] = meshgrid(1:Wm, 1:Hm);
    fluidGrid = interp2(Xpx, Ypx, double(maskPix), X, Y, 'nearest', 0) > 0.5;
else
    % U의 NaN 위치를 mask 영역으로 (모든 프레임의 공통 NaN)
    U0 = pivData.U;
    if ndims(U0) == 3
        % 모든 프레임에서 NaN인 점만 mask로 (= 영구 마스크 영역)
        fluidGrid = ~all(isnan(U0), 3);
    else
        fluidGrid = ~isnan(U0);
    end
end

% (c) 마스크 경계로부터 유체쪽으로 BandWidth 안쪽인 점만
%     = "fluid 영역 안에서 mask와의 거리가 0 < d <= BandWidth"
%     이렇게 하면 유체 깊숙한 곳(자유 흐름)은 제외하고
%     "마스크 표면 근방의 유체점"만 후보가 됨
%
% 격자 간격 추정
dx = mean(diff(unique(X(1,:))));  if isnan(dx)||dx<=0, dx = 8; end
dy = mean(diff(unique(Y(:,1))));  if isnan(dy)||dy<=0, dy = 8; end
gridStep = mean([dx, dy]);
bandSteps = max(1, ceil(opt.BandWidth / gridStep));

% bwdist: 격자상에서 mask까지의 거리 (스텝 단위)
% mask = ~fluidGrid
distGrid = bwdist(~fluidGrid);   % fluid 안에서 mask까지 거리 [grid steps]
nearMask = (distGrid > 0) & (distGrid <= bandSteps);

% (d) 결합
searchMask = inROI & fluidGrid & nearMask;
end


% =========================================================================
% 보조 2: 격자상 (iy, ix) 주변 3x3에서 서브픽셀 위치 (점수 max용)
% =========================================================================
function [xs, ys] = local_subpixelMax(X, Y, score, iy, ix)
[Ny, Nx] = size(X);
i1 = max(1, iy-1); i2 = min(Ny, iy+1);
j1 = max(1, ix-1); j2 = min(Nx, ix+1);

patch = score(i1:i2, j1:j2);
% 음수/NaN은 0으로
w = patch;
w(isnan(w) | w < 0) = 0;
W = sum(w(:));
if W <= 0
    xs = X(iy, ix);  ys = Y(iy, ix);
    return;
end
Xp = X(i1:i2, j1:j2);
Yp = Y(i1:i2, j1:j2);
xs = sum(w(:) .* Xp(:)) / W;
ys = sum(w(:) .* Yp(:)) / W;
end


% =========================================================================
% 보조 2b: NaN-safe 국소 평균 (정사각 윈도우 [2*r+1]^2)
% =========================================================================
function meanV = local_localMean(V, r)
mask = ~isnan(V);
Vfilled = V; Vfilled(~mask) = 0;
kern = ones(2*r+1);
num = conv2(Vfilled, kern, 'same');
den = conv2(double(mask), kern, 'same');
meanV = num ./ max(den, eps);
meanV(~mask) = NaN;
end


% =========================================================================
% 보조 3: 가우시안 스무딩 (NaN-safe)
% =========================================================================
function Vs = local_gaussSmooth(V, sigma)
% NaN을 0으로 두고 정규화하는 방식
mask = ~isnan(V);
Vfilled = V;  Vfilled(~mask) = 0;

% 커널 크기
rad = max(1, ceil(3*sigma));
[gx, gy] = meshgrid(-rad:rad, -rad:rad);
g = exp(-(gx.^2 + gy.^2) / (2*sigma^2));
g = g / sum(g(:));

% conv2
num = conv2(Vfilled, g, 'same');
den = conv2(double(mask), g, 'same');
Vs = num ./ max(den, eps);
Vs(~mask) = NaN;
end


% =========================================================================
% 보조 4: 디버그 시각화
% =========================================================================
function local_plotDebug(X, Y, pivData, searchMask, opt)
figure('Name', 'MAENG_FindStagnationPoint v2 — DEBUG', 'Color', 'w');
U0 = pivData.U;  if ndims(U0)==3, U0 = U0(:,:,1); end
V0 = pivData.V;  if ndims(V0)==3, V0 = V0(:,:,1); end
Umag = sqrt(U0.^2 + V0.^2);

imagesc(X(1,:), Y(:,1), Umag);
axis equal tight; hold on;
set(gca, 'YDir','reverse', 'Color',[0.85 0.85 0.85]);
try, caxis(opt.ColorRange); catch, end
colorbar;

% ROI 박스
if ~isempty(opt.ROI)
    r = opt.ROI;
    plot([r(1) r(2) r(2) r(1) r(1)], [r(3) r(3) r(4) r(4) r(3)], ...
        '-', 'Color', [1 0.5 0], 'LineWidth', 2);
    text(r(1), r(3), ' ROI', 'Color',[1 0.5 0], 'FontWeight','bold', ...
        'VerticalAlignment','bottom');
end

% 검색 마스크 (반투명 빨간 점)
[iyS, ixS] = find(searchMask);
xs = X(sub2ind(size(X), iyS, ixS));
ys = Y(sub2ind(size(Y), iyS, ixS));
plot(xs, ys, '.', 'Color', [1 0 0], 'MarkerSize', 10);

title(sprintf(['DEBUG — orange box: ROI, red dots: search points (%d). ' ...
    '정체점은 이 빨간 점들 중에서 |V|가 가장 작은 곳으로 잡힙니다.'], ...
    numel(xs)), 'FontSize', 10);
xlabel('x [px]'); ylabel('y [px]');
drawnow;
end


% =========================================================================
% 보조 5: 수평 보조선 (yline 호환)
% =========================================================================
function local_hline(yVal, lineStyle, lineColor, label, Nt)
if isnan(yVal) || isinf(yVal), return; end
xl = xlim;
if all(xl == [0 1]), xl = [1, max(2,Nt)]; end
plot(xl, [yVal yVal], lineStyle, 'Color', lineColor, 'LineWidth', 1.0);
if ~isempty(label)
    text(xl(1), yVal, [' ' label], 'VerticalAlignment','bottom', ...
        'FontSize', 9, 'Color', lineColor);
end
end


% =========================================================================
% 보조 6: pivQuiver fallback
% =========================================================================
function local_fallbackBg(X, Y, Uk, Vk, cLo, cHi)
Umag = sqrt(Uk.^2 + Vk.^2);
imagesc(X(1,:), Y(:,1), Umag, [cLo, cHi]);
axis equal tight;
set(gca, 'YDir', 'reverse', 'Color', [0.85 0.85 0.85]);
end
