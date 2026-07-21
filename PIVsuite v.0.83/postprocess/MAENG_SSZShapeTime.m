function out = MAENG_SSZShapeTime(pivData)
% MAENG_SSZShapeTime — 정체영역(SSZ 아래)을 레이크 정렬 좌표로, 시간축에 적층한 3D
% --------------------------------------------------------------------------
% SSZ = 레이크 접선 방향 각 단면에서 Vy가 절단값(=칩 Vy의 SSZ_FRAC)과 같아지는 점.
% 정체영역 = 그 SSZ선 아래(툴 쪽, Vy가 절단값 미만인 영역) 전체.
%
% [기울기 제거] 절대좌표(이미지 X-Y) 대신 '레이크 정렬 좌표'로 그림:
%     X = 레이크면에서의 깊이(칩 쪽),  Z = 레이크 따라 위치,  Y = 시간(ms)
%   → 레이크가 축이 되어 SSZ가 기울지 않고 곧게 섬.
%
% [완전 채움] 단면이 전부 정체(교차 없음, Vy 전부 절단값 미만)인 곳은
%     깊이 끝까지 채움 → 절삭날 근처 등 '왼쪽 아래'가 비지 않음.
%
% ★ 실행: F5 → 프레임 범위 →
%   ① SSZ 방향(레이크면 따라, 우상→좌하) 2점  ② 칩 쪽 두께 폭 점 1개  → 자동
%
% [출력 figure] 메인 정체영역을 두 장으로:
%   (8-1) ISO metric 3D 뷰
%   (8-2) Time축을 화면 안쪽으로 보낸 Depth–Along 2D 투영 뷰
%
% [논문용 옵션]
%   - Depth(X)축 방향 뒤집기(XDIR_REVERSE)
%   - Depth(X)/Along(Z)/Time(Y) 축 범위 고정(DEPTH_LIM/ALONG_LIM/TIME_LIM)
%   - 시간(컬러바 포함) 0 ms부터 시작(TIME_FROM_ZERO)
%   - Depth:Along = 1:1 물리 스케일 유지(고정 범위 반영) → 두 조건 그림 직접 비교
%   - 600 dpi PNG + vector PDF 저장(SAVE_FIG) — 파일명에 _ISO / _2D 접미사
%
% 출력 out: .frames .t_ms .roiPoly .SSZ_FRAC .VY_CUT .st_disp
%           .sszDepth(셀) .stagDepth(셀) .depth_mean .stagArea .unit
% --------------------------------------------------------------------------

%% ===================== 사용자 설정 =====================
FPS         = 2000;     % [Hz]    ※ 데이터셋 확인
px2um       = 2.34;     % [um/px] ※ 데이터셋 확인
FRAME_START = [850];       % 비우면 inputdlg
FRAME_END   = [1150];
FRAME_STEP  = 50;
SSZ_FRAC    = 0.30;     % SSZ 절단 = 칩 Vy의 이 비율 (자동, 창 없음)
SMOOTH_SIG  = 1.0;      % Vy 가우시안 σ [grid cell]
N_STATION   = 60;       % 레이크 방향 단면 개수
N_NORMAL    = 150;      % 단면당 깊이 탐색 점수
DISP_NSLICES= 15;       % 3D 시간 슬라이스 개수
UNIT_UM     = true;     % 축 um(false=px)
ISO_AZEL    = [-45 35.264];   % ISO metric 뷰 (azimuth, elevation)  ※ +45로 좌우반전 가능

% ── 논문용 축 / 스케일 / 시간 옵션 ─────────────────────────────
XDIR_REVERSE  = true;    % Depth(X)축 방향 뒤집기
DEPTH_LIM     = [0 150];      % Depth from rake (X) 고정 [min max] 표시단위, []=자동  (예: [0 250])
ALONG_LIM     = [0 200];      % Along rake     (Z) 고정 [min max] 표시단위, []=자동  (예: [0 800])
TIME_FROM_ZERO= true;    % 시간(컬러바 포함)을 첫 프레임 = 0 ms 기준으로
TIME_LIM      = [];      % 시간축/컬러바 고정 [min max] ms, []=자동             (예: [0 375])
SAVE_FIG      = false;   % true면 두 그림을 PNG(600dpi)+PDF(vector)로 저장
SAVE_NAME     = 'SSZ_region';      % 저장 파일명(확장자 제외, pwd 기준 / 전체경로 가능)
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
if TIME_FROM_ZERO
    t_ms = (frames - frames(1))/FPS*1000;   % 첫 프레임 = 0 ms (상대시간)
else
    t_ms = (frames - 1)/FPS*1000;           % 절대시간
end

% [3] 기준 Vy(시간평균) + 배경 ----------------------------------------
V_mean  = mean(pivData.V, 3, 'omitnan');
VyMean  = local_nanGauss(V_mean*unitScale, SMOOTH_SIG);   % 부호있는 mm/s
bg      = local_loadBg(pivData, frames(1));

% [4] 방향 사각형 ROI — 선 그릴 때는 원본 이미지만 ---------------------
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
title('① SSZ 방향(레이크면 따라, 우상 → 좌하) 2점 클릭');
[xc, yc] = ginput(2);
p1 = [xc(1) yc(1)];  p2 = [xc(2) yc(2)];
u   = (p2 - p1); u = u / max(norm(u), eps);    % 레이크 접선 (s_t 방향)
nrm = [-u(2) u(1)];                            % 두께 법선
plot([p1(1) p2(1)], [p1(2) p2(2)], '-', 'Color',[1 0.85 0], 'LineWidth',2.5);
plot(p1(1), p1(2), 'o', 'Color',[1 0.85 0], 'MarkerFaceColor',[1 0.85 0]);
title('② 칩 쪽으로 두께 폭 점 1개 클릭');
[x3, y3] = ginput(1);
w = ([x3 y3] - p1) * nrm.';
if w < 0, nrm = -nrm;  w = -w;  end            % 법선을 칩 쪽(+)으로 정규화: 깊이 0=기준선
L1 = norm(p2 - p1);
corners = [p1; p2; p2 + w*nrm; p1 + w*nrm];
roiX = corners(:,1);  roiY = corners(:,2);
plot([roiX; roiX(1)], [roiY; roiY(1)], '-', 'Color',[1 0.4 0], 'LineWidth',2);
pause(0.4);
try close(figR); catch; end
roiPoly = [roiX roiY];
inROI = inpolygon(X, Y, roiX, roiY);

% [5] Vy 절단값 = 칩 Vy의 SSZ_FRAC (자동) -----------------------------
vyROI = VyMean(inROI & isfinite(VyMean));
if isempty(vyROI), error('ROI 안에 유효한 Vy가 없습니다.'); end
p05 = local_prctile(vyROI,5);  p95 = local_prctile(vyROI,95);
if abs(p05) >= abs(p95), vchipS = p05; else, vchipS = p95; end   % 부호 포함 칩 Vy
VY_CUT = SSZ_FRAC * vchipS;
fprintf('>> ROI Vy 범위: %.1f ~ %.1f mm/s | 칩 Vy ≈ %.1f | 절단=%.0f%%·칩 = %.1f mm/s\n', ...
        min(vyROI), max(vyROI), vchipS, SSZ_FRAC*100, VY_CUT);

% [6] 단면 교차 → SSZ 깊이 / 정체 채움 깊이 (px) ----------------------
s_t = linspace(0, L1, N_STATION);     % 레이크 방향 [px]
s_n = linspace(0, w,  N_NORMAL);      % 깊이(기준선=0 → 칩쪽=w) [px]
[Sn, St] = meshgrid(s_n, s_t);        % N_STATION × N_NORMAL
Qx = p1(1) + St*u(1) + Sn*nrm(1);
Qy = p1(2) + St*u(2) + Sn*nrm(2);

sszD  = cell(1,nF);   stagD = cell(1,nF);     % 깊이 프로파일 [px]
for k = 1:nF
    f  = frames(k);
    Vy = local_nanGauss(double(pivData.V(:,:,f))*unitScale, SMOOTH_SIG);
    Vq = interp2(X, Y, Vy, Qx, Qy, 'linear');
    dssz  = nan(1,N_STATION);
    dstag = nan(1,N_STATION);
    for i = 1:N_STATION
        prof = Vq(i,:);  val = isfinite(prof);
        if nnz(val) < 2, continue; end
        prof = interp1(s_n(val), prof(val), s_n, 'linear');
        fi = find(isfinite(prof));
        if numel(fi) < 2, continue; end
        d  = prof - VY_CUT;
        sg = sign(d(fi));
        c  = find(sg(1:end-1).*sg(2:end) < 0, 1, 'first');   % 기준선 쪽 첫 교차
        if ~isempty(c)
            a = fi(c);  b = fi(c+1);
            if d(a) ~= d(b)
                tt  = d(a)/(d(a)-d(b));
                snc = s_n(a) + tt*(s_n(b)-s_n(a));
                dssz(i)  = snc;     % SSZ 경계 깊이
                dstag(i) = snc;     % 정체영역 = 0 ~ snc
            end
        else                                          % 교차 없음 = 단면 전부 한쪽
            medv = median(prof(fi),'omitnan');
            if (medv - VY_CUT)*vchipS < 0             % 전부 정체 → 깊이 끝까지 채움
                dstag(i) = s_n(fi(end));
            else                                       % 전부 칩 → 채움 없음
                dstag(i) = 0;
            end
        end
    end
    sszD{k} = dssz;  stagD{k} = dstag;
end

% 표시단위 환산 + 정량
st_disp    = s_t * sc;                          % 레이크 위치 [표시단위]
dst        = (st_disp(2) - st_disp(1));
depth_mean = cellfun(@(d) mean(d,'omitnan'), sszD) * sc;            % SSZ 평균 깊이
stagArea   = cellfun(@(d) sum(d(isfinite(d)))*sc, stagD) * dst;     % 정체영역 면적
covg = mean(cellfun(@(d) mean(isfinite(d)), sszD)) * 100;
fprintf('>> SSZ 경계 적중률 평균 %.0f%% | 유효 프레임 %d/%d\n', covg, nnz(isfinite(depth_mean)), nF);

% [7] 검증 그림 (이미지 좌표) — 정체영역 채움 + SSZ선 -----------------
kmid = max(1, round(nF/2));
figure('Name','검증: 정체영역/SSZ 위치','Color','w','NumberTitle','off');
local_backdrop(bg);
hV = imagesc(X(1,:), Y(:,1)', VyMean); set(hV,'AlphaData',0.55*double(~isnan(VyMean)));
colormap(gca, local_divCmap());
A = max(abs([p05 p95]));  if ~(A>0), A = max(abs(vyROI)); end
try, clim([-A A]); catch, caxis([-A A]); end
cb = colorbar; cb.Label.String = 'V_y (mm/s)';
axis image; set(gca,'YDir','reverse');
plot([roiPoly(:,1); roiPoly(1,1)], [roiPoly(:,2); roiPoly(1,2)], '--','Color',[1 0.6 0],'LineWidth',1.2);
[pxg, pyg] = local_regionImg(sszD{kmid}, stagD{kmid}, s_t, p1, u, nrm);   % 이미지좌표 폴리곤/선
if ~isempty(pxg.fillX)
    patch('XData',pxg.fillX,'YData',pyg.fillY,'FaceColor',[0.2 0.55 1],'FaceAlpha',0.30,'EdgeColor','none');
end
if ~isempty(pxg.lineX)
    plot(pxg.lineX, pyg.lineY, '-', 'Color',[0 0 0], 'LineWidth',3.0);
    plot(pxg.lineX, pyg.lineY, '-', 'Color',[0 1 1], 'LineWidth',1.5);
end
xlabel('X [px]'); ylabel('Y [px]');
title(sprintf('검증: frame %d 정체영역(파랑)/SSZ선(청록, %.0f%%·Vchip)', frames(kmid), SSZ_FRAC*100));

% [8] 메인 — 두 가지 뷰: ISO metric 3D / Time축 제거한 2D ----------------
%     X=깊이(정체/BUE 높이), Z=레이크 따라 부착 길이, Y=시간
cmapT   = local_timeCmap(nF);
drawIdx = unique(round(linspace(1, nF, min(DISP_NSLICES, nF))));
cfg = struct('sc',sc, 'st_disp',st_disp, 't_ms',t_ms, 'cmapT',cmapT, ...
             'drawIdx',drawIdx, 'ulab',ulab, 'SSZ_FRAC',SSZ_FRAC, ...
             'XDIR_REVERSE',XDIR_REVERSE, 'DEPTH_LIM',DEPTH_LIM, ...
             'ALONG_LIM',ALONG_LIM, 'TIME_LIM',TIME_LIM, 'ISO_AZEL',ISO_AZEL);

% (8-1) ISO metric 3D 뷰 ----------------------------------------------
figISO = figure('Name','정체영역 시간진화 — ISO metric 3D','Color','w', ...
                'NumberTitle','off','Position',[100 110 980 720]);
axI = axes(figISO);
local_drawSSZ(axI, 'iso', stagD, sszD, cfg);
title(axI, sprintf('Stagnation region over time (ISO)  |  cut = %.0f%%·V_{chip}', SSZ_FRAC*100), ...
      'FontWeight','bold','FontSize',12,'Interpreter','tex');

% (8-2) Time축 제거 → Depth–Along 2D 투영 뷰 ---------------------------
fig2D = figure('Name','정체영역 — Time 제거 2D (Depth–Along)','Color','w', ...
               'NumberTitle','off','Position',[1100 110 760 720]);
ax2 = axes(fig2D);
local_drawSSZ(ax2, '2d', stagD, sszD, cfg);
title(ax2, sprintf('Stagnation region, time-collapsed  |  cut = %.0f%%·V_{chip}', SSZ_FRAC*100), ...
      'FontWeight','bold','FontSize',12,'Interpreter','tex');

% 논문용 저장 (선택) — 두 그림 각각 PNG(600dpi)+PDF(vector) ----------
if SAVE_FIG
    exportgraphics(figISO,[SAVE_NAME '_ISO.png'],'Resolution',600,'BackgroundColor','white');
    exportgraphics(figISO,[SAVE_NAME '_ISO.pdf'],'ContentType','vector','BackgroundColor','white');
    exportgraphics(fig2D, [SAVE_NAME '_2D.png'], 'Resolution',600,'BackgroundColor','white');
    exportgraphics(fig2D, [SAVE_NAME '_2D.pdf'], 'ContentType','vector','BackgroundColor','white');
    fprintf('>> 저장: %s_ISO / %s_2D  (.png 600dpi + .pdf vector)\n', SAVE_NAME, SAVE_NAME);
end

% [9] 정량 — SSZ 깊이 & 정체영역 면적 vs 시간 -------------------------
auni = 'um'; if ~UNIT_UM, auni = 'px'; end
figure('Name','SSZ 깊이 & 정체면적 vs 시간','Color','w','NumberTitle','off','Position',[220 150 760 430]);
subplot(1,2,1);
plot(t_ms, depth_mean, '-o', 'Color',[0 0.3 0.7], 'MarkerFaceColor',[0 0.3 0.7],'MarkerSize',3.5,'LineWidth',1.6);
grid on; xlabel('Time (ms)'); ylabel(['SSZ depth ' ulab]);
title(sprintf('SSZ 깊이: mean=%.1f, std=%.1f %s', mean(depth_mean,'omitnan'), std(depth_mean,'omitnan'), auni));
subplot(1,2,2);
plot(t_ms, stagArea, '-o', 'Color',[0.7 0.2 0.2], 'MarkerFaceColor',[0.7 0.2 0.2],'MarkerSize',3.5,'LineWidth',1.6);
grid on; xlabel('Time (ms)'); ylabel(['Stagnation area ' auni '^2']);
title(sprintf('정체면적: mean=%.0f, std=%.0f', mean(stagArea,'omitnan'), std(stagArea,'omitnan')));

fprintf('>> SSZ 깊이 mean=%.1f %s (std=%.1f) | 정체면적 mean=%.0f %s^2 (std=%.0f)\n', ...
        mean(depth_mean,'omitnan'), auni, std(depth_mean,'omitnan'), ...
        mean(stagArea,'omitnan'), auni, std(stagArea,'omitnan'));

% [10] 출력 -----------------------------------------------------------
out = struct();
out.frames = frames;  out.t_ms = t_ms;  out.roiPoly = roiPoly;
out.SSZ_FRAC = SSZ_FRAC;  out.VY_CUT = VY_CUT;  out.st_disp = st_disp;
out.sszDepth = cellfun(@(d) d*sc, sszD, 'UniformOutput',false);
out.stagDepth = cellfun(@(d) d*sc, stagD, 'UniformOutput',false);
out.depth_mean = depth_mean;  out.stagArea = stagArea;  out.unit = ulab;

end % ===================== main 끝 =====================


%% ========================================================================
%% 보조 0b: 정체영역 콘텐츠 렌더 (mode='iso' | '2d') — 두 뷰 공용
%% ========================================================================
function local_drawSSZ(ax, mode, stagD, sszD, cfg)
    hold(ax,'on');
    drawIdx = cfg.drawIdx;  sc = cfg.sc;  st_disp = cfg.st_disp;
    t_ms    = cfg.t_ms;     cmapT = cfg.cmapT;

    % --- 시간 슬라이스 적층 (정체 채움 + SSZ 경계선) ---
    for k = drawIdx
        dS = stagD{k}*sc;  vd = isfinite(dS);                 % 정체 채움
        if any(vd)
            DX = [dS(vd), zeros(1,nnz(vd))];                  % 깊이 (X): 외곽 → 0
            AZ = [st_disp(vd), fliplr(st_disp(vd))];          % 레이크 부착 길이 (Z)
            fill3(ax, DX, t_ms(k)*ones(size(DX)), AZ, cmapT(k,:), 'FaceAlpha',0.25,'EdgeColor','none');
        end
        dL = sszD{k}*sc;  vl = isfinite(dL);                  % SSZ 경계선
        if any(vl)
            plot3(ax, dL(vl), t_ms(k)*ones(1,nnz(vl)), st_disp(vl), '-','Color',cmapT(k,:),'LineWidth',1.8);
        end
    end

    % --- 라벨 / 그리드 ---
    xlabel(ax, ['Depth from rake ' cfg.ulab], 'FontWeight','bold');   % 정체/BUE 높이
    ylabel(ax, 'Time (ms)', 'FontWeight','bold');
    zlabel(ax, ['Along rake ' cfg.ulab], 'FontWeight','bold');        % 부착 길이
    grid(ax,'on'); set(ax,'GridAlpha',0.2);

    % --- 축 방향 / 범위 고정 (두 뷰 공통) ---
    if cfg.XDIR_REVERSE, set(ax,'XDir','reverse'); end        % Depth(X)축 뒤집기
    if ~isempty(cfg.DEPTH_LIM), xlim(ax, cfg.DEPTH_LIM); end   % Depth(X) 고정
    if ~isempty(cfg.ALONG_LIM), zlim(ax, cfg.ALONG_LIM); end   % Along rake(Z) 고정
    if ~isempty(cfg.TIME_LIM),  ylim(ax, cfg.TIME_LIM);  end   % Time(Y) 고정

    % --- 컬러바(시간) ---
    colormap(ax, cmapT);
    if isempty(cfg.TIME_LIM), tclim = [min(t_ms) max(t_ms)]; else, tclim = cfg.TIME_LIM; end
    if diff(tclim) <= 0, tclim = tclim(1) + [-0.5 0.5]; end
    try, clim(ax, tclim); catch, caxis(ax, tclim); end
    cb = colorbar(ax); cb.Label.String = 'Time (ms)';

    % --- 뷰별 처리 ---
    switch lower(mode)
        case 'iso'      % ── ISO metric 3D ─────────────────────────
            box(ax,'on'); set(ax,'BoxStyle','full');
            view(ax, cfg.ISO_AZEL(1), cfg.ISO_AZEL(2));
            % X(깊이)·Z(부착길이) 등척 → Depth:Along = 1:1, 시간축(Y)만 비례
            xl = xlim(ax);  zl = zlim(ax);  yl = ylim(ax);
            sp = max(diff(xl), diff(zl));
            if diff(yl) > 0 && sp > 0
                daspect(ax, [1, diff(yl)/sp, 1]);
            end
        case '2d'       % ── Time축 제거 → Depth–Along 평면 ────────
            view(ax, 0, 0);              % Y(Time)축을 화면 안쪽으로 → 시간 붕괴
            daspect(ax, [1 1 1]);        % Depth:Along = 1:1
            box(ax,'on'); set(ax,'BoxStyle','back');
            ylabel(ax, '');              % 보이지 않는 Time축 라벨 제거
            set(ax,'YTick',[]);          % Time 눈금/그리드 제거(화면 정리)
        otherwise
            view(ax, 3);
    end
    hold(ax,'off');
end

%% ========================================================================
%% 보조 0: 깊이 프로파일 → 이미지좌표 폴리곤/선 (검증용)
%% ========================================================================
function [PX, PY] = local_regionImg(dssz, dstag, s_t, p1, u, nrm)
    % 정체 채움 폴리곤
    vd = isfinite(dstag);
    if any(vd)
        ox = p1(1) + s_t(vd)*u(1) + dstag(vd)*nrm(1);
        oy = p1(2) + s_t(vd)*u(2) + dstag(vd)*nrm(2);
        bx = p1(1) + s_t(vd)*u(1);
        by = p1(2) + s_t(vd)*u(2);
        PX.fillX = [ox, fliplr(bx)];   PY.fillY = [oy, fliplr(by)];
    else
        PX.fillX = [];  PY.fillY = [];
    end
    % SSZ 경계선
    vl = isfinite(dssz);
    if any(vl)
        PX.lineX = p1(1) + s_t(vl)*u(1) + dssz(vl)*nrm(1);
        PY.lineY = p1(2) + s_t(vl)*u(2) + dssz(vl)*nrm(2);
    else
        PX.lineX = [];  PY.lineY = [];
    end
end

%% ========================================================================
%% 보조 1: NaN-safe 가우시안
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
%% 보조 2: 발산형 컬러맵 (파랑=음 / 흰=0 / 빨강=양)
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
%% 보조 3: 시간 컬러맵 (파랑=초기 → 빨강=후기)
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
%% 보조 4: 무차원 백분위
%% ========================================================================
function p = local_prctile(v, q)
    v = sort(v(:));
    if isempty(v), p = NaN; return; end
    idx = max(1, min(numel(v), round(q/100*numel(v))));
    p = v(idx);
end

%% ========================================================================
%% 보조 5: 배경 깔기
%% ========================================================================
function local_backdrop(bg)
    if ~isempty(bg)
        b = bg; if size(b,3)==1, b = repmat(b,1,1,3); end
        image([0 size(b,2)-1], [0 size(b,1)-1], b);
    end
    hold on;
end

%% ========================================================================
%% 보조 6: 배경 이미지 로드
%% ========================================================================
function bg = local_loadBg(pivData, k)
    bg = []; fn = '';
    if isfield(pivData,'imFilename1') && ~isempty(pivData.imFilename1)
        fn = pivData.imFilename1;
    elseif isfield(pivData,'imFilename2') && ~isempty(pivData.imFilename2)
        fn = pivData.imFilename2;
    end
    if iscell(fn)
        fn = fn{min(max(k,1), numel(fn))};
    elseif isstring(fn) && numel(fn) > 1
        fn = char(fn(min(max(k,1), numel(fn))));
    else
        fn = char(fn);
    end
    if ~isempty(fn) && exist(fn,'file')==2
        try, bg = imread(fn); catch, bg = []; end
    end
end