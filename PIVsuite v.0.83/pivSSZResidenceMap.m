function D = pivSSZResidenceMap(out)
% pivSSZResidenceMap — SSZ 체류시간을 속도장에서 바로 음영으로 (느릴수록 진함)
% --------------------------------------------------------------------------
% 체류시간 τ(x,y) ≈ (길이 w) / |V(x,y)|.
%   느린 곳(데드메탈/정체)  → τ 큼 → 진하게  (오래 머묾)
%   빠른 곳(칩 흐름)         → τ 작음 → 옅게  (금방 지나감)
% 시간평균 속도장 한 장으로 계산 → 사진 딱 한 장. 프레임 누적 없음.
%
%   50  : 느린 데드메탈 코어가 크고 진함  → 오래 머묾 → 변형 누적 → BUE
%   100 : 코어가 작고 옅음(전반적으로 빠름) → 덜 머묾 → no BUE
%
% ★ 실행 (둘 다 가능)
%   (단독)  ▶/F5 만 누르면 됨 → 프레임 범위(미리 채움) → ROI 2점+두께 클릭
%   (재사용) shp = pivSSZShapeTime;  D = pivSSZResidenceMap(shp);
%            → out의 ROI/프레임/SSZ깊이/칩속도를 그대로 사용
%   pivData는 base workspace에서 자동 로드.
%
% 출력 D: .tau_ms(맵) .speed(μm/ms) .w_um .climMax .roiPoly .frames
% --------------------------------------------------------------------------

%% ===================== 사용자 설정 =====================
FPS         = 2000;    % [Hz]    ※ 데이터셋 확인
px2um       = 2.34;    % [um/px] ※ 데이터셋 확인
FRAME_START = 850;     % (단독 실행) 비우면 inputdlg
FRAME_END   = 1600;
FRAME_STEP  = 50;
W_UM        = [];      % 길이 스케일 [um] 직접지정(비우면: out=평균SSZ깊이 / 단독=ROI두께)
SMOOTH_SIG  = 1.5;     % 속도 가우시안 σ [grid cell]
ALPHA       = 0.90;    % 최대 불투명도
VFLOOR_FR   = 0.02;    % 속도 하한 = 칩속도의 이 비율 (τ 발산 방지)
CLIP_PCT    = 95;      % 컬러 상한 = ROI 내 τ의 이 백분위
ZOOM_ROI    = true;
%% =======================================================

haveOut = (nargin >= 1) && isstruct(out) && isfield(out,'roiPoly');

% [1] pivData 로드 (base) ----------------------------------------------
try
    pivData = evalin('base','pivData');
catch
    error('workspace에 pivData가 없습니다 (grid/속도 필요).');
end
X = double(pivData.X);  Y = double(pivData.Y);  Nt = size(pivData.U,3);
unitScale = px2um*FPS/1000;            % px/frame → mm/s = μm/ms

% [2] 프레임 범위 ------------------------------------------------------
if haveOut
    frames = out.frames(:).';
else
    if isempty(FRAME_START) || isempty(FRAME_END)
        dlg = inputdlg({sprintf('시작 프레임 (1~%d):',Nt), ...
                        sprintf('끝 프레임 (1~%d):',Nt), '간격:'}, ...
                       '시간 범위', 1, {'1', num2str(Nt), '1'});
        if isempty(dlg), disp('취소됨'); D = []; return; end
        FRAME_START = round(str2double(dlg{1}));
        FRAME_END   = round(str2double(dlg{2}));
        FRAME_STEP  = max(1, round(str2double(dlg{3})));
    end
    frames = FRAME_START:FRAME_STEP:FRAME_END;
end
frames = frames(frames>=1 & frames<=Nt);
if isempty(frames), error('유효 프레임이 없습니다.'); end

% [3] 시간평균 속도 (분석 프레임 창) -----------------------------------
Umean = mean(pivData.U(:,:,frames), 3, 'omitnan');
Vmean = mean(pivData.V(:,:,frames), 3, 'omitnan');
Us = local_nanGauss(Umean*unitScale, SMOOTH_SIG);
Vs = local_nanGauss(Vmean*unitScale, SMOOTH_SIG);
speed  = hypot(Us, Vs);                 % [μm/ms]
VyMean = Vs;                            % ROI 칩속도 판정용 (부호있음)

% [4] ROI / 길이 w / 칩속도 — out 재사용 or 직접 ----------------------
if haveOut
    rp = out.roiPoly;
    sc = 1; if isfield(out,'unit') && contains(lower(char(out.unit)),'mu'), sc = px2um; end
    if ~isempty(W_UM)
        w_um = W_UM;
    else
        w_um = (mean(out.depth_mean,'omitnan')/sc) * px2um;     % 평균 SSZ 깊이 [um]
    end
    if isfield(out,'VY_CUT') && isfield(out,'SSZ_FRAC')
        Vchip = abs(out.VY_CUT / out.SSZ_FRAC);
    else
        Vchip = NaN;
    end
    fprintf('>> out 재사용: ROI/프레임(%d개)  w=%.1f μm\n', numel(frames), w_um);
else
    % --- ROI 클릭 (pivSSZShapeTime과 동일 UX) ---
    bg0 = local_loadBg(pivData, frames(1));
    figR = figure('Name','ROI 지정 (방향 사각형)','Color','w','NumberTitle','off');
    if ~isempty(bg0)
        local_backdrop(bg0);
    else
        hMb = imagesc(X(1,:), Y(:,1)', VyMean);
        set(hMb,'AlphaData',0.5*double(~isnan(VyMean)));
        colormap(gca, local_divCmap()); hold on;
    end
    axis image; set(gca,'YDir','reverse'); xlabel('X [px]'); ylabel('Y [px]');
    title('① SSZ 방향(레이크면 따라, 우상 → 좌하) 2점 클릭');
    [xc, yc] = ginput(2);  p1 = [xc(1) yc(1)];  p2 = [xc(2) yc(2)];
    u = (p2 - p1)/max(norm(p2 - p1), eps);  nrm = [-u(2) u(1)];
    plot([p1(1) p2(1)], [p1(2) p2(2)], '-','Color',[1 0.85 0],'LineWidth',2.5);
    plot(p1(1), p1(2), 'o','Color',[1 0.85 0],'MarkerFaceColor',[1 0.85 0]);
    title('② 칩 쪽으로 두께 폭 점 1개 클릭');
    [x3, y3] = ginput(1);  wpx = ([x3 y3] - p1) * nrm.';
    if wpx < 0, nrm = -nrm;  wpx = -wpx;  end
    rp = [p1; p2; p2 + wpx*nrm; p1 + wpx*nrm];
    plot([rp(:,1); rp(1,1)], [rp(:,2); rp(1,2)], '-','Color',[1 0.4 0],'LineWidth',2);
    pause(0.3); try close(figR); catch; end
    % 칩속도 (ROI Vy 5/95 백분위 중 절댓값 큰 쪽)
    inR = inpolygon(X, Y, rp(:,1), rp(:,2));
    vyROI = VyMean(inR & isfinite(VyMean));
    if isempty(vyROI), error('ROI 안에 유효한 Vy가 없습니다.'); end
    p05 = local_prctile(vyROI,5);  p95 = local_prctile(vyROI,95);
    if abs(p05) >= abs(p95), Vchip = abs(p05); else, Vchip = abs(p95); end
    if ~isempty(W_UM), w_um = W_UM; else, w_um = wpx * px2um; end   % 길이 = ROI 두께
    fprintf('>> 칩속도 ≈ %.1f μm/ms | w(ROI두께)=%.1f μm\n', Vchip, w_um);
end

% [5] 체류시간 τ = w / |V| --------------------------------------------
if ~isfinite(Vchip) || Vchip<=0, Vchip = max(speed(:),[],'omitnan'); end
vfloor = VFLOOR_FR * Vchip;
tau_ms = w_um ./ max(speed, vfloor);            % [ms]
tau_ms(~isfinite(speed)) = NaN;

inROI = inpolygon(X, Y, rp(:,1), rp(:,2)) & isfinite(tau_ms);
tROI = tau_ms(inROI);
climMax = local_prctile(tROI, CLIP_PCT);  if ~(climMax>0), climMax = max(tROI); end

% [6] 그림 ------------------------------------------------------------
bg = local_loadBg(pivData, frames(1));
figure('Name','SSZ 체류시간 (느릴수록 진함)','Color','w','NumberTitle','off','Position',[180 130 880 720]);
local_backdrop(bg);
hd = imagesc(X(1,:), Y(:,1)', tau_ms);
A = ALPHA * min(1, tau_ms./max(climMax,eps)) .* double(inROI);   % 오래(진함)일수록 불투명
A(isnan(A)) = 0;
set(hd, 'AlphaData', A);
colormap(gca, local_resCmap());                 % 옅음(짧음) → 진함(긺)
try, clim([0 climMax]); catch, caxis([0 climMax]); end
cb = colorbar; cb.Label.String = 'Residence time  \tau \approx w/|V|  [ms]';
axis image; set(gca,'YDir','reverse'); hold on;
plot([rp(:,1); rp(1,1)], [rp(:,2); rp(1,2)], '--','Color',[0.2 0.8 1],'LineWidth',1.2);

if ZOOM_ROI
    padx = 0.10*(max(rp(:,1))-min(rp(:,1))) + 5;
    pady = 0.10*(max(rp(:,2))-min(rp(:,2))) + 5;
    xlim([min(rp(:,1))-padx, max(rp(:,1))+padx]);
    ylim([min(rp(:,2))-pady, max(rp(:,2))+pady]);
end
xlabel('X [px]'); ylabel('Y [px]');
title(sprintf('SSZ 체류시간 (진할수록 오래 머묾)  |  w=%.1f μm, 상한 %.2f ms', w_um, climMax));

fprintf('>> 체류시간 맵: w=%.1f μm, 칩속도=%.1f μm/ms | τ 상한(%d%%)=%.2f ms\n', ...
        w_um, Vchip, CLIP_PCT, climMax);

% [7] 출력 ------------------------------------------------------------
D = struct();
D.tau_ms = tau_ms;  D.speed = speed;  D.w_um = w_um;
D.climMax = climMax;  D.roiPoly = rp;  D.frames = frames;

end % ===================== main 끝 =====================


%% ========================================================================
%% 보조: NaN-safe 가우시안
%% ========================================================================
function Vo = local_nanGauss(V, sigma)
    if sigma <= 0, Vo = V; return; end
    mask = ~isnan(V);
    Vf = V; Vf(~mask) = 0;
    rad = max(1, ceil(3*sigma));
    [gx, gy] = meshgrid(-rad:rad, -rad:rad);
    g = exp(-(gx.^2 + gy.^2)/(2*sigma^2));  g = g/sum(g(:));
    num = conv2(Vf, g, 'same');
    den = conv2(double(mask), g, 'same');
    Vo = num ./ max(den, eps);
    Vo(den < 0.10) = NaN;
end

%% ========================================================================
%% 보조: 체류 컬러맵 (옅은 노랑=짧음 → 진한 적갈=긺)
%% ========================================================================
function c = local_resCmap()
    pts = [0.00 1.00 1.00 0.85;
           0.45 0.95 0.45 0.10;
           0.80 0.55 0.05 0.05;
           1.00 0.22 0.00 0.00];
    t = linspace(0,1,256)';
    c = [interp1(pts(:,1),pts(:,2),t,'pchip'), ...
         interp1(pts(:,1),pts(:,3),t,'pchip'), ...
         interp1(pts(:,1),pts(:,4),t,'pchip')];
    c = max(0, min(1, c));
end

%% ========================================================================
%% 보조: 발산형 컬러맵 (단독 실행 ROI 배경용)
%% ========================================================================
function c = local_divCmap()
    n = 256;  t = linspace(0,1,n)';
    c1 = [0.23 0.30 0.75];  c2 = [1 1 1];  c3 = [0.75 0.15 0.15];
    c = zeros(n,3);
    for j = 1:3
        c(:,j) = interp1([0 0.5 1], [c1(j) c2(j) c3(j)], t, 'linear');
    end
end

%% ========================================================================
%% 보조: 무차원 백분위
%% ========================================================================
function p = local_prctile(v, q)
    v = sort(v(isfinite(v)));
    if isempty(v), p = NaN; return; end
    idx = max(1, min(numel(v), round(q/100*numel(v))));
    p = v(idx);
end

%% ========================================================================
%% 보조: 배경 깔기
%% ========================================================================
function local_backdrop(bg)
    if ~isempty(bg)
        b = bg; if size(b,3)==1, b = repmat(b,1,1,3); end
        image([0 size(b,2)-1], [0 size(b,1)-1], b);
    end
    hold on;
end

%% ========================================================================
%% 보조: 배경 이미지 로드
%% ========================================================================
function bg = local_loadBg(pivData, k)
    bg = []; fn = '';
    if isfield(pivData,'imFilename1') && ~isempty(pivData.imFilename1)
        fn = pivData.imFilename1;
    elseif isfield(pivData,'imFilename2') && ~isempty(pivData.imFilename2)
        fn = pivData.imFilename2;
    end
    if iscell(fn), fn = fn{min(max(k,1),numel(fn))};
    elseif isstring(fn) && numel(fn)>1, fn = char(fn(min(max(k,1),numel(fn))));
    else, fn = char(fn); end
    if ~isempty(fn) && exist(fn,'file')==2
        try, bg = imread(fn); catch, bg = []; end
    end
end