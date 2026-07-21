function sszData = MAENG_SSZExtract(pivData, varargin)
% MAENG_SSZExtract — 단일 프레임에서 SSZ(이차전단대) 고전단 밴드 추출
% --------------------------------------------------------------------------
% 한 프레임의 PIV 속도장으로부터 전단율 맵을 만들고, 사용자가 지정한 ROI
% 사각형 안에서 "전단이 높은 띠(=SSZ 밴드)"를 임계화·연결요소로 뽑아냅니다.
%
% [v2 변경점 — SSZ 가시성/빈칸 문제 해결]
%   • SSZ는 rake/BUE 접촉면 옆(=PIV 상관도 최저)이라 그 자리가 NaN이면
%     raw 미분으로는 전단이 구멍에 빠져 안 보임. → 속도장을 inpaint로 채운 뒤
%     미분해야 칩속도↔정체(≈0)의 점프가 살아나 SSZ가 드러남.
%   • 단일 γ_xy 성분은 띠가 기울면 과소평가 → 좌표 무관한 '최대전단'을 기본 신호로.
%   • 채운 뒤 데이터에서 너무 먼 셀(배경)만 다시 NaN으로 비워 정직성 유지.
%
% ★ 실행법 1 (F5 / ▶): 인자 없이 → pivData 자동 로드 → 프레임 입력
%     → ROI 사각형 드래그 → 밴드 추출/표시
% ★ 실행법 2 (오버레이 단계 호출):
%     ssz = MAENG_SSZExtract(pivData,'Frame',120,'ROI',[x1 x2 y1 y2],'Show',false);
%
% 출력 sszData:
%   .frame .roi .S(전단맵, 채움/스무딩됨) .thr .bandMask
%   .outlineX/Y(외곽선,px)  .cx/.cy(전단가중 무게중심,px)  .area_px
%   .signal  .X .Y
% --------------------------------------------------------------------------

%% ================= 사용자 설정 (상단 일괄) =================
FRAME         = [];          % 분석 프레임. 비우면 inputdlg
ROI_RECT      = [];          % [x1 x2 y1 y2] px. 비우면 마우스 드래그
SIGNAL        = 'maxshear';  % 'maxshear'(좌표무관·권장) / 'shear'(γxy) / 'eff'(von Mises)

FILL_HOLES    = true;        % 미분 전 속도장 NaN 채움 (SSZ 가시화 핵심)
MAX_FILL_DIST = 4;           % 채운 뒤, 원본 데이터에서 이 거리[grid cell]보다 먼 셀은
                             %   다시 NaN(배경 비움). 전부 채우려면 Inf.
SMOOTH_VEL    = 1.0;         % 속도장 가우시안 σ [grid cell] (노이즈 제어 주력)
SMOOTH_STRAIN = 0.6;         % 전단장 가우시안 σ [grid cell] (밴드 결 다듬기), 0=off

THRESH_FRAC   = 0.55;        % 밴드 임계 = THRESH_FRAC × (ROI 내 피크 전단)
PEAK_PRCTILE  = 99;          % 피크 기준 백분위 (max 대신: 스파이크 강건)
THRESH_FLOOR  = 0.05;        % 절대 하한 [프레임당 무차원 전단] — ROI가 조용할 때 노이즈 차단
CLOSE_RAD     = 1;           % imclose 반경 [grid cell] (끊긴 밴드 연결)

SHOW          = true;        % 결과 figure 표시
mmPerPx       = 0.00468;     % px→mm (검출엔 무영향, 콘솔 보고용)
VIS_COLORMAP  = 'turbo';
VIS_ALPHA     = 0.65;
%% ==========================================================

% ---- (F5 모드) pivData 자동 로드 --------------------------------------
if nargin < 1 || isempty(pivData)
    try
        pivData = evalin('base', 'pivData');
        fprintf('[MAENG_SSZExtract] base 워크스페이스의 pivData 사용\n');
    catch
        [fn, fp] = uigetfile({'*.mat','MAT-files (*.mat)'}, 'pivData가 담긴 .mat 선택');
        if isequal(fn,0), error('취소되었습니다.'); end
        Sload   = load(fullfile(fp, fn));
        pivData = local_findPivStruct(Sload);
    end
end

% ---- 이름-값 인자 오버라이드 -----------------------------------------
for a = 1:2:numel(varargin)
    key = varargin{a}; val = varargin{a+1};
    switch lower(key)
        case 'frame',        FRAME         = val;
        case 'roi',          ROI_RECT      = val;
        case 'signal',       SIGNAL        = val;
        case 'show',         SHOW          = logical(val);
        case 'fillholes',    FILL_HOLES    = logical(val);
        case 'maxfilldist',  MAX_FILL_DIST = val;
        case 'smoothvel',    SMOOTH_VEL    = val;
        case 'smoothstrain', SMOOTH_STRAIN = val;
        case 'threshfrac',   THRESH_FRAC   = val;
        case 'threshfloor',  THRESH_FLOOR  = val;
        otherwise, warning('알 수 없는 옵션: %s', key);
    end
end

% ---- 차원/격자 -------------------------------------------------------
if ndims(pivData.U) < 3, Nt = 1; else, [~,~,Nt] = size(pivData.U); end
X = double(pivData.X);
Y = double(pivData.Y);
if isfield(pivData,'iaStepX') && ~isempty(pivData.iaStepX)
    dx = double(pivData.iaStepX); else, dx = median(diff(X(1,:)),'omitnan'); end
if isfield(pivData,'iaStepY') && ~isempty(pivData.iaStepY)
    dy = double(pivData.iaStepY); else, dy = median(diff(Y(:,1)),'omitnan'); end
if ~(dx>0), dx = 1; end
if ~(dy>0), dy = 1; end

% ---- 프레임 선택 -----------------------------------------------------
if isempty(FRAME)
    def    = num2str(max(1, round(Nt/2)));
    ans_in = inputdlg(sprintf('분석할 프레임 (1 ~ %d):', Nt), 'SSZ 프레임', 1, {def});
    if isempty(ans_in), error('취소되었습니다.'); end
    FRAME = round(str2double(ans_in{1}));
end
if ~isfinite(FRAME), error('프레임 번호가 올바르지 않습니다.'); end
FRAME = max(1, min(Nt, FRAME));

% ---- 해당 프레임 속도장 (raw, NaN 유지) ------------------------------
if Nt == 1
    Uk = double(pivData.U);  Vk = double(pivData.V);
else
    Uk = double(pivData.U(:,:,FRAME));  Vk = double(pivData.V(:,:,FRAME));
end
validRaw = ~isnan(Uk) & ~isnan(Vk);     % 원본 유효 벡터 위치 (배경 재마스킹 기준)

% ---- 빈칸 채움 + 스무딩 → 연속 속도장 → 전단 -------------------------
if FILL_HOLES
    Uf = inpaint_nans(Uk, 4);            % 프로젝트의 inpaint_nans (method 4)
    Vf = inpaint_nans(Vk, 4);
    if SMOOTH_VEL > 0
        Uf = local_nanGauss(Uf, SMOOTH_VEL);   % 이미 NaN 없음 → 순수 가우시안
        Vf = local_nanGauss(Vf, SMOOTH_VEL);
    end
    [dUdx, dUdy] = gradient(Uf, dx, dy);       % 채운 뒤엔 중심차분(벡터화, 빠름)
    [dVdx, dVdy] = gradient(Vf, dx, dy);
else
    [dUdx, dUdy] = robust_nan_gradient(Uk, dx, dy);  % raw 모드: NaN-aware 편측차분
    [dVdx, dVdy] = robust_nan_gradient(Vk, dx, dy);
end

exx = dUdx;  eyy = dVdy;  exy = 0.5*(dUdy + dVdx);
switch lower(SIGNAL)
    case 'maxshear'
        S = sqrt((exx - eyy).^2 + (2*exy).^2);          % 최대 공학전단 (좌표 무관)
    case 'shear'
        S = abs(dUdy + dVdx);                            % γ_xy 성분
    case 'eff'
        S = sqrt((2/3)*(exx.^2 + eyy.^2 + 2*exy.^2));    % von Mises 효과변형률
    otherwise
        error('SIGNAL은 ''maxshear'', ''shear'', ''eff'' 중 하나.');
end
if SMOOTH_STRAIN > 0
    S = local_nanGauss(S, SMOOTH_STRAIN);
end

% ---- 데이터에서 너무 먼 셀(배경)만 다시 비움 -------------------------
if FILL_HOLES && isfinite(MAX_FILL_DIST)
    distG = bwdist(validRaw);            % 각 셀 → 가장 가까운 원본 유효셀 거리 [grid cell]
    S(distG > MAX_FILL_DIST) = NaN;      % 재료 내부 작은 구멍은 유지, 멀리 배경은 비움
end

% ---- 배경 이미지 ------------------------------------------------------
bg = local_loadFrameImage(pivData, FRAME);

% ---- 색 범위 (스파이크가 SSZ 대비를 죽이지 않도록 99% 클램프) --------
finV = S(isfinite(S));
cmax = local_prctile(finV, 99);
if ~(cmax>0) && ~isempty(finV), cmax = max(finV); end
if ~(cmax>0), cmax = 1; end

% ---- ROI 미지정 시: 전체 전단맵 띄우고 사각형 드래그 ----------------
if isempty(ROI_RECT)
    figROI = figure('Name','ROI 지정','Color','w');
    local_drawBackdrop(bg, X, Y);
    [~, hc] = contourf(X, Y, S, 80, 'LineStyle','none');
    try, alpha(hc, VIS_ALPHA); catch, end
    colormap(VIS_COLORMAP); colorbar;
    try, clim([0 cmax]); catch, caxis([0 cmax]); end
    axis equal tight; set(gca,'YDir','reverse');
    title('SSZ 밴드를 감싸도록 사각형을 드래그하세요','FontSize',12);
    r = getrect(figROI);
    ROI_RECT = [r(1), r(1)+r(3), r(2), r(2)+r(4)];
    if ishghandle(figROI), close(figROI); end
    fprintf('[MAENG_SSZExtract] ROI = [%.1f %.1f %.1f %.1f] px\n', ROI_RECT);
end

% ---- ROI 내 밴드 임계화 ----------------------------------------------
inROI = (X>=ROI_RECT(1)) & (X<=ROI_RECT(2)) & (Y>=ROI_RECT(3)) & (Y<=ROI_RECT(4));
valid = inROI & isfinite(S);
if ~any(valid(:))
    error('ROI 안에 유효한 전단값이 없습니다. ROI 또는 MAX_FILL_DIST를 조정하세요.');
end

peakVal  = local_prctile(S(valid), PEAK_PRCTILE);
thr      = max(THRESH_FLOOR, THRESH_FRAC * peakVal);
bandMask = valid & (S >= thr);

% ---- 형태학 정리 → 최대(전단합) 연결요소 -----------------------------
if CLOSE_RAD > 0
    bandMask = imclose(bandMask, strel('disk', CLOSE_RAD));
end
bandMask = imfill(bandMask, 'holes') & inROI;
CC = bwconncomp(bandMask, 8);
if CC.NumObjects == 0
    warning('밴드가 비었습니다. THRESH_FRAC/THRESH_FLOOR를 낮춰보세요.');
elseif CC.NumObjects > 1
    sc = cellfun(@(idx) sum(S(idx),'omitnan'), CC.PixelIdxList);
    [~, best] = max(sc);
    keep = false(size(bandMask)); keep(CC.PixelIdxList{best}) = true;
    bandMask = keep;
end

% ---- 전단가중 무게중심 -----------------------------------------------
bm = bandMask & isfinite(S);
if any(bm(:))
    w  = S(bm);
    cx = sum(X(bm).*w)/sum(w);
    cy = sum(Y(bm).*w)/sum(w);
else
    cx = NaN; cy = NaN;
end

% ---- 외곽선 폴리곤 ---------------------------------------------------
outlineX = []; outlineY = [];
B = bwboundaries(bandMask, 8, 'noholes');
if ~isempty(B)
    [~, bi] = max(cellfun(@(b) size(b,1), B));
    rc  = B{bi};
    ind = sub2ind(size(X), rc(:,1), rc(:,2));
    outlineX = X(ind);  outlineY = Y(ind);
end
area_px = nnz(bandMask) * dx * dy;

% ---- 결과 구조체 -----------------------------------------------------
sszData = struct('frame',FRAME, 'roi',ROI_RECT, 'S',S, 'thr',thr, ...
    'bandMask',bandMask, 'outlineX',outlineX, 'outlineY',outlineY, ...
    'cx',cx, 'cy',cy, 'area_px',area_px, 'signal',lower(SIGNAL), 'X',X, 'Y',Y);

cover = 100 * nnz(valid) / max(1, nnz(inROI));   % ROI 내 유효 셀 비율
fprintf(['[MAENG_SSZExtract] frame=%d  signal=%s  ROI유효=%.0f%%  thr=%.3f  ' ...
         'band셀=%d  centroid=(%.1f,%.1f)px=(%.3f,%.3f)mm\n'], ...
    FRAME, lower(SIGNAL), cover, thr, nnz(bandMask), cx, cy, cx*mmPerPx, cy*mmPerPx);

% ---- 결과 시각화 -----------------------------------------------------
if SHOW
    figure('Name', sprintf('SSZ band — frame %d', FRAME), 'Color','w');
    local_drawBackdrop(bg, X, Y);
    Sshow = S; Sshow(~inROI) = NaN;
    [~, hc] = contourf(X, Y, Sshow, 80, 'LineStyle','none');
    try, alpha(hc, VIS_ALPHA); catch, end
    colormap(VIS_COLORMAP);
    try, clim([0 cmax]); catch, caxis([0 cmax]); end
    cb = colorbar; ylabel(cb, '전단율  [/frame]');

    if ~isempty(outlineX)
        plot(outlineX, outlineY, '-', 'Color',[0 0.85 0.85], 'LineWidth',2.2);
    end
    if isfinite(cx)
        plot(cx, cy, 'o', 'MarkerSize',10, 'LineWidth',2, ...
            'MarkerEdgeColor','w', 'MarkerFaceColor',[1 0.2 0.2]);
    end
    r = ROI_RECT;
    plot([r(1) r(2) r(2) r(1) r(1)], [r(3) r(3) r(4) r(4) r(3)], ...
        '--', 'Color',[1 0.6 0], 'LineWidth',1.2);
    axis equal tight; set(gca,'YDir','reverse'); box on;
    xlabel('x [px]'); ylabel('y [px]');
    title(sprintf('SSZ band (frame %d, %s, thr=%.3f)', FRAME, lower(SIGNAL), thr), ...
        'FontSize',12, 'Interpreter','tex');
end

end % ===================== main 함수 끝 =====================


%% ========================================================================
%% 보조 1: NaN-인지 편측 미분 (raw 모드 fallback; MAENG_EffStrain 규약)
%% ========================================================================
function [dFdx, dFdy] = robust_nan_gradient(F, dx, dy)
    [Ny, Nx] = size(F);
    dFdx = nan(Ny, Nx);  dFdy = nan(Ny, Nx);
    for i = 1:Ny
        for j = 1:Nx
            if isnan(F(i,j)), continue; end
            hasL = (j>1)  && ~isnan(F(i,j-1));
            hasR = (j<Nx) && ~isnan(F(i,j+1));
            if hasL && hasR,     dFdx(i,j) = (F(i,j+1)-F(i,j-1))/(2*dx);
            elseif hasL,         dFdx(i,j) = (F(i,j)  -F(i,j-1))/dx;
            elseif hasR,         dFdx(i,j) = (F(i,j+1)-F(i,j))  /dx;  end
            hasU = (i>1)  && ~isnan(F(i-1,j));
            hasD = (i<Ny) && ~isnan(F(i+1,j));
            if hasU && hasD,     dFdy(i,j) = (F(i+1,j)-F(i-1,j))/(2*dy);
            elseif hasU,         dFdy(i,j) = (F(i,j)  -F(i-1,j))/dy;
            elseif hasD,         dFdy(i,j) = (F(i+1,j)-F(i,j))  /dy;  end
        end
    end
end

%% ========================================================================
%% 보조 2: NaN-safe 가우시안 스무딩
%% ========================================================================
function Vs = local_nanGauss(V, sigma)
    mask = ~isnan(V);
    Vf = V; Vf(~mask) = 0;
    rad = max(1, ceil(3*sigma));
    [gx, gy] = meshgrid(-rad:rad, -rad:rad);
    g   = exp(-(gx.^2 + gy.^2)/(2*sigma^2));  g = g/sum(g(:));
    num = conv2(Vf, g, 'same');
    den = conv2(double(mask), g, 'same');
    Vs  = num ./ max(den, eps);
    Vs(~mask) = NaN;
end

%% ========================================================================
%% 보조 3: 무차원 백분위 (Statistics Toolbox 의존 제거)
%% ========================================================================
function p = local_prctile(v, q)
    v = sort(v(:));
    if isempty(v), p = NaN; return; end
    idx = max(1, min(numel(v), round(q/100*numel(v))));
    p   = v(idx);
end

%% ========================================================================
%% 보조 4: 배경 프레임 이미지 로드
%% ========================================================================
function bg = local_loadFrameImage(pivData, k)
    bg = []; fn = '';
    if isfield(pivData,'imFilename2') && ~isempty(pivData.imFilename2)
        fn = pivData.imFilename2;
    elseif isfield(pivData,'imFilename1') && ~isempty(pivData.imFilename1)
        fn = pivData.imFilename1;
    end
    if iscell(fn), fn = fn{min(k, numel(fn))}; end
    if (ischar(fn) || isstring(fn)) && exist(char(fn),'file')==2
        try, bg = imread(char(fn)); catch, bg = []; end
    end
end

%% ========================================================================
%% 보조 5: 배경(이미지 또는 회색) 깔기
%% ========================================================================
function local_drawBackdrop(bg, X, Y)
    if ~isempty(bg)
        if size(bg,3)==1, bg = repmat(bg,[1 1 3]); end
        image([1 size(bg,2)], [1 size(bg,1)], bg);
    else
        xl = [min(X(:)) max(X(:))]; yl = [min(Y(:)) max(Y(:))];
        patch([xl(1) xl(2) xl(2) xl(1)], [yl(1) yl(1) yl(2) yl(2)], ...
              [0.85 0.85 0.85], 'EdgeColor','none');
    end
    hold on;
end

%% ========================================================================
%% 보조 6: .mat에서 PIV 구조체 탐색
%% ========================================================================
function pd = local_findPivStruct(S)
    pd = []; fn = fieldnames(S);
    for k = 1:numel(fn)
        v = S.(fn{k});
        if isstruct(v) && isfield(v,'X') && isfield(v,'U') && isfield(v,'V')
            pd = v; return;
        end
    end
    error('.mat 안에서 X/U/V 필드를 가진 PIV 구조체를 찾지 못했습니다.');
end