function out = MAENG_SSZBandExtract(pivData)
% MAENG_SSZBandExtract — SSZ 밴드(전단층)를 프레임마다 추출, 레이크정렬 3D로 시간 적층
% --------------------------------------------------------------------------
% SSZ 밴드 = 각 단면(레이크 접선)에서 Vy가 칩속도의 FRAC_LO~FRAC_HI 인 구간.
%   안쪽(툴) 가장자리 = Vy = FRAC_LO·Vchip,  바깥(칩) 가장자리 = Vy = FRAC_HI·Vchip
%   두께 = (바깥 깊이 − 안쪽 깊이).
%
% MAENG_SSZShapeTime과 동일 구조 (per-frame → 3D iso + 2D 검증 + 두께 vs 시간).
% 다른 점: '정체영역(0~SSZ선)' 대신 '밴드(d_lo~d_hi)'를 채우고 두께를 잰다.
%
% [레이크 정렬] X=레이크 깊이, Z=레이크 위치, Y=시간  → 밴드가 기울지 않음.
%
% ★ 실행: F5 → 프레임 범위 → ① 레이크 따라 2점(우상→좌하) ② 칩쪽 두께 1점
%
% 출력 out: .frames .t_ms .roiPoly .FRAC_LO .FRAC_HI .st_disp
%           .bandLo(셀) .bandHi(셀) .thick(셀) .thick_mean .center_mean .unit
% --------------------------------------------------------------------------

%% ===================== 사용자 설정 =====================
FPS         = 2000;     % [Hz]    ※ 데이터셋 확인
px2um       = 2.34;     % [um/px] ※ 데이터셋 확인
FRAME_START = 850;      % 비우면 inputdlg
FRAME_END   = 1150;
FRAME_STEP  = 50;
FRAC_LO     = 0.20;     % 밴드 안쪽(툴쪽) = 칩 Vy의 이 비율
FRAC_HI     = 0.60;     % 밴드 바깥(칩쪽) = 칩 Vy의 이 비율
SMOOTH_SIG  = 1.0;      % Vy 가우시안 σ [grid cell]
N_STATION   = 60;       % 레이크 방향 단면 개수
N_NORMAL    = 150;      % 단면당 깊이 탐색 점수
DISP_NSLICES= 15;       % 3D 시간 슬라이스 개수
UNIT_UM     = true;     % 축 um(false=px)
VIEW_AZEL   = [-35 18]; % 3D 시점
%% =======================================================

% [1] pivData 로드 ------------------------------------------------------
if nargin < 1 || isempty(pivData)
    try
        pivData = evalin('base','pivData');
        fprintf('>> [자동] workspace에서 pivData 로드\n');
    catch
        error('workspace에 pivData가 없습니다.');
    end
end
X = double(pivData.X);  Y = double(pivData.Y);  Nt = size(pivData.U,3);
unitScale = px2um*FPS/1000;            % px/frame → mm/s
sc = 1; if UNIT_UM, sc = px2um; end    % px → 표시단위
ulab = '[\mum]'; if ~UNIT_UM, ulab = '[px]'; end

% [2] 프레임 범위 ------------------------------------------------------
if isempty(FRAME_START) || isempty(FRAME_END)
    dlg = inputdlg({sprintf('시작 프레임 (1~%d):',Nt), ...
                    sprintf('끝 프레임 (1~%d):',Nt), '간격:'}, ...
                   '시간 범위', 1, {'1', num2str(Nt), '1'});
    if isempty(dlg), disp('취소됨'); out = []; return; end
    FRAME_START = round(str2double(dlg{1}));
    FRAME_END   = round(str2double(dlg{2}));
    FRAME_STEP  = max(1, round(str2double(dlg{3})));
end
frames = FRAME_START:FRAME_STEP:FRAME_END;
frames = frames(frames>=1 & frames<=Nt);
nF = numel(frames);
if nF < 2, error('시간 진화를 보려면 프레임이 2개 이상이어야 합니다.'); end
t_ms = (frames-1)/FPS*1000;

% [3] 기준 Vy(시간평균) + 배경 ----------------------------------------
V_mean  = mean(pivData.V, 3, 'omitnan');
VyMean  = local_nanGauss(V_mean*unitScale, SMOOTH_SIG);   % 부호있는 mm/s
bg      = local_loadBg(pivData, frames(1));

% [4] 방향 사각형 ROI ---------------------------------------------------
figR = figure('Name','ROI 지정 (방향 사각형)','Color','w','NumberTitle','off');
if ~isempty(bg)
    local_backdrop(bg);
else
    hMb = imagesc(X(1,:), Y(:,1)', VyMean);
    set(hMb,'AlphaData',0.5*double(~isnan(VyMean)));
    colormap(gca, local_divCmap()); hold on;
end
axis image; set(gca,'YDir','reverse');
xlabel('X [px]'); ylabel('Y [px]');
title('① 밴드 방향(레이크면 따라, 우상 → 좌하) 2점 클릭');
[xc, yc] = ginput(2);
p1 = [xc(1) yc(1)];  p2 = [xc(2) yc(2)];
u   = (p2 - p1); u = u / max(norm(u), eps);    % 레이크 접선
nrm = [-u(2) u(1)];                            % 두께 법선
plot([p1(1) p2(1)], [p1(2) p2(2)], '-', 'Color',[1 0.85 0], 'LineWidth',2.5);
plot(p1(1), p1(2), 'o', 'Color',[1 0.85 0], 'MarkerFaceColor',[1 0.85 0]);
title('② 칩 쪽으로 두께 폭 점 1개 클릭');
[x3, y3] = ginput(1);
w = ([x3 y3] - p1) * nrm.';
if w < 0, nrm = -nrm;  w = -w;  end            % 법선을 칩 쪽(+)으로: 깊이 0=기준선(툴)
L1 = norm(p2 - p1);
corners = [p1; p2; p2 + w*nrm; p1 + w*nrm];
roiX = corners(:,1);  roiY = corners(:,2);
plot([roiX; roiX(1)], [roiY; roiY(1)], '-', 'Color',[1 0.4 0], 'LineWidth',2);
pause(0.4);
try close(figR); catch; end
roiPoly = [roiX roiY];
inROI = inpolygon(X, Y, roiX, roiY);

% [5] Vy 칩속도 → 밴드 절단값 두 개 (자동) ----------------------------
vyROI = VyMean(inROI & isfinite(VyMean));
if isempty(vyROI), error('ROI 안에 유효한 Vy가 없습니다.'); end
p05 = local_prctile(vyROI,5);  p95 = local_prctile(vyROI,95);
if abs(p05) >= abs(p95), vchipS = p05; else, vchipS = p95; end   % 부호 포함 칩 Vy
cut_lo = FRAC_LO * vchipS;
cut_hi = FRAC_HI * vchipS;
fprintf('>> 칩 Vy ≈ %.1f mm/s | 밴드 %.0f~%.0f%% = %.1f ~ %.1f mm/s\n', ...
        vchipS, FRAC_LO*100, FRAC_HI*100, cut_lo, cut_hi);

% [6] 단면 교차 → 밴드 안/바깥 깊이 (px), 프레임마다 -------------------
s_t = linspace(0, L1, N_STATION);     % 레이크 방향 [px]
s_n = linspace(0, w,  N_NORMAL);      % 깊이(툴=0 → 칩쪽=w) [px]
[Sn, St] = meshgrid(s_n, s_t);
Qx = p1(1) + St*u(1) + Sn*nrm(1);
Qy = p1(2) + St*u(2) + Sn*nrm(2);

bandLo = cell(1,nF);  bandHi = cell(1,nF);
for k = 1:nF
    f  = frames(k);
    Vy = local_nanGauss(double(pivData.V(:,:,f))*unitScale, SMOOTH_SIG);
    Vq = interp2(X, Y, Vy, Qx, Qy, 'linear');
    dlo = nan(1,N_STATION);   dhi = nan(1,N_STATION);
    for i = 1:N_STATION
        prof = Vq(i,:);  val = isfinite(prof);
        if nnz(val) < 2, continue; end
        pf = interp1(s_n(val), prof(val), s_n, 'linear');
        fi = find(isfinite(pf));  if numel(fi) < 2, continue; end
        dlo(i) = cross_level(pf, fi, s_n, cut_lo);   % 안쪽(툴) 가장자리
        dhi(i) = cross_level(pf, fi, s_n, cut_hi);   % 바깥(칩) 가장자리
    end
    bandLo{k} = dlo;  bandHi{k} = dhi;
end

% 표시단위 환산 + 정량 (밴드 두께 / 중심 깊이) ------------------------
st_disp    = s_t * sc;                          % 레이크 위치 [표시단위]
thick      = cell(1,nF);
thick_mean = nan(1,nF);   center_mean = nan(1,nF);
for k = 1:nF
    th = bandHi{k} - bandLo{k};  th(th <= 0) = NaN;     % 두께 [px]
    thick{k}       = th * sc;                           % [표시단위]
    thick_mean(k)  = mean(th,'omitnan') * sc;
    ctr = (bandHi{k} + bandLo{k})/2;                    % 밴드 중심 깊이 [px]
    center_mean(k) = mean(ctr,'omitnan') * sc;
end
covg = mean(cellfun(@(lo,hi) mean(isfinite(hi-lo) & (hi-lo)>0), bandLo, bandHi)) * 100;
fprintf('>> 밴드 적중률 평균 %.0f%% | 두께 mean=%.1f %s (std=%.1f) | 유효프레임 %d/%d\n', ...
        covg, mean(thick_mean,'omitnan'), strrep(ulab,'\mu','u'), std(thick_mean,'omitnan'), ...
        nnz(isfinite(thick_mean)), nF);

% [7] 검증 그림 (이미지 좌표) — 밴드 채움 + 양 가장자리 ----------------
kmid = max(1, round(nF/2));
figure('Name','검증: SSZ 밴드 위치','Color','w','NumberTitle','off');
local_backdrop(bg);
hV = imagesc(X(1,:), Y(:,1)', VyMean); set(hV,'AlphaData',0.55*double(~isnan(VyMean)));
colormap(gca, local_divCmap());
A = max(abs([p05 p95]));  if ~(A>0), A = max(abs(vyROI)); end
try, clim([-A A]); catch, caxis([-A A]); end
cb = colorbar; cb.Label.String = 'V_y (mm/s)';
axis image; set(gca,'YDir','reverse');
plot([roiPoly(:,1); roiPoly(1,1)], [roiPoly(:,2); roiPoly(1,2)], '--','Color',[1 0.6 0],'LineWidth',1.2);
[PF, LI, LO] = local_bandImg(bandLo{kmid}, bandHi{kmid}, s_t, p1, u, nrm);
if ~isempty(PF.X)
    patch('XData',PF.X,'YData',PF.Y,'FaceColor',[0.1 0.9 0.5],'FaceAlpha',0.35,'EdgeColor','none');
    plot(LI.X, LI.Y, '-','Color',[0 0 0],'LineWidth',2.4); plot(LI.X, LI.Y, '-','Color',[0.1 1 0.4],'LineWidth',1.1);
    plot(LO.X, LO.Y, '-','Color',[0 0 0],'LineWidth',2.4); plot(LO.X, LO.Y, '-','Color',[1 1 0.2],'LineWidth',1.1);
end
xlabel('X [px]'); ylabel('Y [px]');
title(sprintf('검증: frame %d 밴드(초록) | 안쪽=%.0f%%(초록), 바깥=%.0f%%(노랑)·Vchip', ...
      frames(kmid), FRAC_LO*100, FRAC_HI*100));

% [8] 메인 3D — 레이크 정렬, 밴드 리본을 시간 적층 ---------------------
%     X=깊이, Z=레이크 위치, Y=시간
cmapT = local_timeCmap(nF);
figure('Name','SSZ 밴드 시간 진화 (레이크 정렬)','Color','w', ...
       'NumberTitle','off','Position',[150 110 1000 700]);
ax = axes; hold(ax,'on');
drawIdx = unique(round(linspace(1, nF, min(DISP_NSLICES, nF))));
for k = drawIdx
    lo = bandLo{k}*sc;  hi = bandHi{k}*sc;
    vd = isfinite(lo) & isfinite(hi) & (hi-lo)>0;            % 밴드 채움
    if any(vd)
        DX = [hi(vd), fliplr(lo(vd))];                      % 깊이(X): 바깥 → 안쪽
        AZ = [st_disp(vd), fliplr(st_disp(vd))];            % 레이크 위치(Z)
        fill3(ax, DX, t_ms(k)*ones(size(DX)), AZ, cmapT(k,:), 'FaceAlpha',0.25,'EdgeColor','none');
    end
    vl = isfinite(lo);                                       % 안쪽 가장자리
    if any(vl), plot3(ax, lo(vl), t_ms(k)*ones(1,nnz(vl)), st_disp(vl), '-','Color',cmapT(k,:),'LineWidth',1.4); end
    vh = isfinite(hi);                                       % 바깥 가장자리
    if any(vh), plot3(ax, hi(vh), t_ms(k)*ones(1,nnz(vh)), st_disp(vh), '-','Color',cmapT(k,:),'LineWidth',1.4); end
end
xlabel(ax, ['Depth from rake ' ulab], 'FontWeight','bold');
ylabel(ax, 'Time (ms)', 'FontWeight','bold');
zlabel(ax, ['Along rake ' ulab], 'FontWeight','bold');
title(ax, sprintf('SSZ band over time (rake-aligned)  |  %.0f~%.0f%%·V_{chip}', FRAC_LO*100, FRAC_HI*100), ...
      'FontWeight','bold','FontSize',12,'Interpreter','tex');
% (Along rake 위아래 뒤집기: 아래 한 줄 주석 해제)
% set(ax,'ZDir','reverse');
view(ax, VIEW_AZEL(1), VIEW_AZEL(2));
grid(ax,'on'); box(ax,'on'); set(ax,'BoxStyle','full','GridAlpha',0.2);
colormap(ax, cmapT);
try, clim(ax,[min(t_ms) max(t_ms)]); catch, caxis(ax,[min(t_ms) max(t_ms)]); end
cb2 = colorbar(ax); cb2.Label.String = 'Time (ms)';
% X(깊이)·Z(레이크) 등척 → 모양 유지. 시간축(Y)만 별도 스케일.
xl = xlim(ax);  zl = zlim(ax);  yl = ylim(ax);
sp = max(diff(xl), diff(zl));
if diff(yl) > 0 && sp > 0, daspect(ax, [1, diff(yl)/sp, 1]); end
hold(ax,'off');

% [9] 정량 — 밴드 두께 & 중심 깊이 vs 시간 ----------------------------
auni = 'um'; if ~UNIT_UM, auni = 'px'; end
figure('Name','밴드 두께 & 중심깊이 vs 시간','Color','w','NumberTitle','off','Position',[220 150 820 430]);
subplot(1,2,1);
plot(t_ms, thick_mean, '-o', 'Color',[0.15 0.45 0.75], 'MarkerFaceColor',[0.15 0.45 0.75],'MarkerSize',3.5,'LineWidth',1.6);
grid on; xlabel('Time (ms)'); ylabel(['Band thickness ' ulab]);
title(sprintf('밴드 두께: mean=%.1f, std=%.1f %s', mean(thick_mean,'omitnan'), std(thick_mean,'omitnan'), auni));
subplot(1,2,2);
plot(t_ms, center_mean, '-o', 'Color',[0.5 0.25 0.6], 'MarkerFaceColor',[0.5 0.25 0.6],'MarkerSize',3.5,'LineWidth',1.6);
grid on; xlabel('Time (ms)'); ylabel(['Band center depth ' ulab]);
title(sprintf('밴드 중심 깊이: mean=%.1f, std=%.1f %s', mean(center_mean,'omitnan'), std(center_mean,'omitnan'), auni));

% [10] 출력 -----------------------------------------------------------
out = struct();
out.frames = frames;  out.t_ms = t_ms;  out.roiPoly = roiPoly;
out.FRAC_LO = FRAC_LO;  out.FRAC_HI = FRAC_HI;  out.st_disp = st_disp;
out.bandLo = cellfun(@(d) d*sc, bandLo, 'UniformOutput',false);
out.bandHi = cellfun(@(d) d*sc, bandHi, 'UniformOutput',false);
out.thick = thick;  out.thick_mean = thick_mean;  out.center_mean = center_mean;
out.unit = ulab;

end % ===================== main 끝 =====================


%% ========================================================================
%% 보조: 레벨 교차 깊이 (툴쪽 첫 교차, 선형보간)
%% ========================================================================
function dc = cross_level(pf, fi, s_n, level)
    dc = NaN;
    d = pf - level;  sg = sign(d(fi));
    c = find(sg(1:end-1).*sg(2:end) < 0, 1, 'first');
    if ~isempty(c)
        a = fi(c);  b = fi(c+1);
        if d(a) ~= d(b)
            tt = d(a)/(d(a)-d(b));
            dc = s_n(a) + tt*(s_n(b)-s_n(a));
        end
    end
end

%% ========================================================================
%% 보조: 깊이 프로파일 두 개 → 이미지좌표 밴드 폴리곤/가장자리선
%% ========================================================================
function [PF, LI, LO] = local_bandImg(dlo, dhi, s_t, p1, u, nrm)
    vd = isfinite(dlo) & isfinite(dhi) & (dhi-dlo)>0;
    if any(vd)
        ox = p1(1)+s_t(vd)*u(1)+dhi(vd)*nrm(1);  oy = p1(2)+s_t(vd)*u(2)+dhi(vd)*nrm(2);  % 바깥(칩)
        ix = p1(1)+s_t(vd)*u(1)+dlo(vd)*nrm(1);  iy = p1(2)+s_t(vd)*u(2)+dlo(vd)*nrm(2);  % 안쪽(툴)
        PF.X = [ox, fliplr(ix)];   PF.Y = [oy, fliplr(iy)];
        LI.X = ix;  LI.Y = iy;     LO.X = ox;  LO.Y = oy;
    else
        PF.X=[]; PF.Y=[]; LI.X=[]; LI.Y=[]; LO.X=[]; LO.Y=[];
    end
end

%% ========================================================================
%% 보조: NaN-safe 가우시안
%% ========================================================================
function Vs = local_nanGauss(V, sigma)
    if sigma <= 0, Vs = V; return; end
    mask = ~isnan(V);
    Vf = V; Vf(~mask) = 0;
    rad = max(1, ceil(3*sigma));
    [gx, gy] = meshgrid(-rad:rad, -rad:rad);
    g = exp(-(gx.^2 + gy.^2)/(2*sigma^2));  g = g/sum(g(:));
    num = conv2(Vf, g, 'same');
    den = conv2(double(mask), g, 'same');
    Vs = num ./ max(den, eps);
    Vs(den < 0.10) = NaN;
end

%% ========================================================================
%% 보조: 발산형 컬러맵
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
%% 보조: 시간 컬러맵 (파랑=초기 → 빨강=후기)
%% ========================================================================
function c = local_timeCmap(n)
    pts = [ 0.00 0.00 0.20 0.85;
            0.50 0.55 0.20 0.70;
            1.00 0.85 0.10 0.10 ];
    t = linspace(0,1,max(n,2))';
    c = [ interp1(pts(:,1),pts(:,2),t,'pchip'), ...
          interp1(pts(:,1),pts(:,3),t,'pchip'), ...
          interp1(pts(:,1),pts(:,4),t,'pchip') ];
    c = max(0, min(1, c));
    if n == 1, c = c(1,:); end
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