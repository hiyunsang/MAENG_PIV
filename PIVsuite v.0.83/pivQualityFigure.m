function pivQualityFigure()
% pivQualityFigure - 논문용 PIV 신뢰도 검증 Figure (ccPeak / SNR)
%
%  Harzallah et al. (2018, Int. J. Mach. Tools Manuf.) 스타일 적용:
%   - 이탤릭 패널 문자 a) b) c) d) (축 좌상단 외곽)
%   - contourf 등고선 맵 + 수평 컬러바(southoutside)
%   - cool(cyan-magenta) 컬러맵, 마스크 영역은 공백(흰색) 처리
%
%  레이아웃 (2x2 tiledlayout):
%   a) Time-averaged ccPeak 맵    b) Time-averaged SNR 맵
%   c) Frame-wise ccPeak 통계     d) Frame-wise SNR 통계
%
%  실행: F5 (base workspace의 pivData 자동 로드, 없으면 MAT 파일 선택)
%  출력: 600 dpi PNG + 벡터 PDF (현재 폴더)

% =====================================================================
% [사용자 설정 영역]
% =====================================================================
FRAME_RANGE   = [];          % 분석 프레임 범위 [시작 끝], [] = 전체
TH_GOOD       = 0.5;         % ccPeak 'Good' 임계값
TH_POOR       = 0.3;         % ccPeak 'Poor' 임계값

% --- 맵(a,b) 표현 ---
MAP_STYLE     = 'contourf';  % 'contourf' (Harzallah 스타일) | 'imagesc'
N_LEVELS      = 12;          % contourf 등고선 레벨 수
CONTOUR_LINES = true;        % 등고선 경계선 표시 여부 (회색 실선)
UPSAMPLE      = 4;           % 맵 업샘플링 배율 (부드러운 등고선용, 1 = 원본)
COLORMAP_NAME = 'cool';      % 'cool'(Harzallah) | 'parula' | 'turbo' 등
CLIM_CC       = [0.3 1.0];   % ccPeak 컬러 범위
CB_TICKS_CC   = [0.3 0.5 0.7 1.0];  % ccPeak 컬러바 눈금
CLIM_SNR      = [];          % SNR 컬러 범위, [] = 자동(2-98% 분위수)

% --- 축 단위 ---
AXIS_UNIT     = 'px';        % 'px' | 'um' (um 선택 시 PX2UM 적용)
PX2UM         = 3.12;        % [um/px] 실험별 보정값 (3.12 또는 4.68)
XAXIS_TIME    = 'frame';     % 'frame' | 'ms' (c,d 패널 가로축)
FPS           = 40000;       % [Hz] 'ms' 선택 시 사용

% --- 시계열(c,d) 표현 ---
SMOOTH_WIN    = 15;          % 이동평균 스무딩 윈도우 [프레임]
SHOW_RAW      = false;       % 스무딩 전 raw median 표시 여부

% --- Figure / 출력 ---
FIG_W_CM      = 17.0;        % Figure 폭 [cm] (Elsevier 2단 = 19cm 이내)
FIG_H_CM      = 13.5;        % Figure 높이 [cm]
FONT          = 'Arial';     % 폰트
FS            = 8;           % 기본 폰트 크기 [pt]
OUT_BASENAME  = 'Fig_PIV_Quality';  % 출력 파일명 (확장자 제외)
EXPORT_PNG    = true;        % PNG 출력 (600 dpi)
DPI           = 600;
EXPORT_PDF    = true;        % 벡터 PDF 출력
% =====================================================================

% =====================================================================
% [1] pivData 자동 로드
% =====================================================================
try
    pivData = evalin('base', 'pivData');
    fprintf('>> [자동] workspace에서 pivData 로드 완료\n');
catch
    [f, p] = uigetfile('*.mat', 'pivData가 포함된 MAT 파일 선택');
    if isequal(f, 0), error('pivData가 없습니다. PIV 분석 먼저 실행하세요.'); end
    S = load(fullfile(p, f));
    if isfield(S, 'pivData')
        pivData = S.pivData;
    else
        fn = fieldnames(S); pivData = S.(fn{1});
    end
    fprintf('>> [파일] %s 에서 pivData 로드 완료\n', f);
end

if ~isfield(pivData, 'ccPeak') || ~isfield(pivData, 'ccPeakSecondary')
    error('pivData에 ccPeak / ccPeakSecondary 필드가 없습니다.');
end

% =====================================================================
% [2] ccPeak / SNR 추출 및 마스크 처리
% =====================================================================
% single -> double 캐스팅 (연산 안정성)
CC  = double(pivData.ccPeak);
CC2 = double(pivData.ccPeakSecondary);
CC2(CC2 <= 0) = NaN;                 % 0/음수 2차 피크 -> SNR 계산 제외
SNR = CC ./ CC2;                     % SNR = ccPeak / ccPeakSecondary

% Status bit 1 (마스크 영역) -> NaN 처리하여 통계/표시에서 제외
if isfield(pivData, 'Status')
    mk = bitget(uint32(pivData.Status), 1) == 1;
    CC(mk)  = NaN;
    SNR(mk) = NaN;
end

% 프레임 범위 적용
Nt_all = size(CC, 3);
if isempty(FRAME_RANGE)
    fr = 1:Nt_all;
else
    fr = max(1, FRAME_RANGE(1)) : min(Nt_all, FRAME_RANGE(2));
end
CC  = CC(:,:,fr);
SNR = SNR(:,:,fr);
Nt  = numel(fr);
fprintf('>> 프레임 %d ~ %d (총 %d개) 분석\n', fr(1), fr(end), Nt);

% =====================================================================
% [3] 시간평균 맵 + 프레임별 통계 계산
% =====================================================================
ccMap = mean(CC,  3, 'omitnan');     % (a) 시간평균 ccPeak 맵
snMap = mean(SNR, 3, 'omitnan');     % (b) 시간평균 SNR 맵

% 프레임별 median / mean (마스크 제외)
ccMed  = squeeze(median(reshape(CC,  [], Nt), 1, 'omitnan'))';
ccMean = squeeze(mean(  reshape(CC,  [], Nt), 1, 'omitnan'))';
snMed  = squeeze(median(reshape(SNR, [], Nt), 1, 'omitnan'))';
snMean = squeeze(mean(  reshape(SNR, [], Nt), 1, 'omitnan'))';

% 이동평균 스무딩
w = min(SMOOTH_WIN, Nt);
ccMedS  = movmean(ccMed,  w, 'omitnan');
ccMeanS = movmean(ccMean, w, 'omitnan');
snMedS  = movmean(snMed,  w, 'omitnan');
snMeanS = movmean(snMean, w, 'omitnan');

% =====================================================================
% [4] 공간 좌표 (단위 변환 + 업샘플링)
% =====================================================================
X0 = pivData.X; Y0 = pivData.Y;
if ndims(X0) == 3, X0 = X0(:,:,1); Y0 = Y0(:,:,1); end

switch lower(AXIS_UNIT)
    case 'um'
        sc = PX2UM; unitStr = '\mum';
    otherwise
        sc = 1;     unitStr = 'px';
end

% 업샘플링 (부드러운 contourf 경계용; NaN 영역은 그대로 공백 유지)
xv = X0(1,:); yv = Y0(:,1);
if UPSAMPLE > 1
    xu = linspace(xv(1), xv(end), numel(xv)*UPSAMPLE);
    yu = linspace(yv(1), yv(end), numel(yv)*UPSAMPLE);
    [XI, YI] = meshgrid(xu, yu);
    ccMapU = interp2(X0, Y0, ccMap, XI, YI, 'linear');
    snMapU = interp2(X0, Y0, snMap, XI, YI, 'linear');
else
    XI = X0; YI = Y0;
    ccMapU = ccMap; snMapU = snMap;
end
XI = XI * sc;  YI = YI * sc;

% SNR 컬러 범위 자동 산정 (2-98% 분위수, Toolbox 비의존)
if isempty(CLIM_SNR)
    v = sort(snMapU(~isnan(snMapU)));
    lo = v(max(1, round(0.02 * numel(v))));
    hi = v(min(numel(v), round(0.98 * numel(v))));
    CLIM_SNR = [floor(lo/10)*10, ceil(hi/10)*10];
end
cbTicksSN = round(linspace(CLIM_SNR(1), CLIM_SNR(2), 4));

% 시계열 가로축
switch lower(XAXIS_TIME)
    case 'ms'
        tAx = (fr - 1) / FPS * 1000;  tLab = 'Time [ms]';
    otherwise
        tAx = fr;                      tLab = 'Frame index';
end

% =====================================================================
% [5] Figure 생성 (2x2 tiledlayout)
% =====================================================================
fig = figure('Units','centimeters', 'Position',[2 2 FIG_W_CM FIG_H_CM], ...
             'Color','w', 'Name','PIV Quality Figure');
tiledlayout(fig, 2, 2, 'TileSpacing','compact', 'Padding','compact');

% ---------- a) Time-averaged ccPeak ----------
ax1 = nexttile;
drawMap(ax1, XI, YI, ccMapU, CLIM_CC, CB_TICKS_CC, 'ccPeak [-]', ...
        MAP_STYLE, N_LEVELS, CONTOUR_LINES, unitStr);
title(ax1, 'Time-averaged ccPeak', 'FontWeight','normal');
panelLabel(ax1, 'a)', FONT, FS);

% ---------- b) Time-averaged SNR ----------
ax2 = nexttile;
drawMap(ax2, XI, YI, snMapU, CLIM_SNR, cbTicksSN, 'SNR [-]', ...
        MAP_STYLE, N_LEVELS, CONTOUR_LINES, unitStr);
title(ax2, 'Time-averaged SNR', 'FontWeight','normal');
panelLabel(ax2, 'b)', FONT, FS);

% ---------- c) Frame-wise ccPeak ----------
ax3 = nexttile; hold(ax3, 'on');
if SHOW_RAW
    plot(ax3, tAx, ccMed, '-', 'Color',[0.65 0.78 1.0], 'LineWidth',0.5);
end
hM = plot(ax3, tAx, ccMedS,  '-', 'Color',[0 0.30 0.80], 'LineWidth',1.2);
hA = plot(ax3, tAx, ccMeanS, '-', 'Color',[0.85 0.10 0.10], 'LineWidth',1.2);
yline(ax3, TH_GOOD, '--k', sprintf('Good > %.1f', TH_GOOD), ...
      'LabelHorizontalAlignment','left', 'FontSize',FS-1, 'FontName',FONT);
yline(ax3, TH_POOR, '--', sprintf('Poor < %.1f', TH_POOR), ...
      'Color',[0.45 0 0], 'LabelHorizontalAlignment','left', ...
      'FontSize',FS-1, 'FontName',FONT);
ylim(ax3, [0 1]);
xlim(ax3, [tAx(1) tAx(end)]);
xlabel(ax3, tLab);  ylabel(ax3, 'ccPeak [-]');
legend(ax3, [hM hA], {'Median','Mean'}, 'Location','southeast', ...
       'Box','off', 'FontSize',FS-1);
title(ax3, 'Frame-wise ccPeak', 'FontWeight','normal');
panelLabel(ax3, 'c)', FONT, FS);

% ---------- d) Frame-wise SNR ----------
ax4 = nexttile; hold(ax4, 'on');
if SHOW_RAW
    plot(ax4, tAx, snMed, '-', 'Color',[0.65 0.78 1.0], 'LineWidth',0.5);
end
hM2 = plot(ax4, tAx, snMedS,  '-', 'Color',[0 0.30 0.80], 'LineWidth',1.2);
hA2 = plot(ax4, tAx, snMeanS, '-', 'Color',[0.85 0.10 0.10], 'LineWidth',1.2);
xlim(ax4, [tAx(1) tAx(end)]);
xlabel(ax4, tLab);  ylabel(ax4, 'SNR [-]');
legend(ax4, [hM2 hA2], {'Median','Mean'}, 'Location','southeast', ...
       'Box','off', 'FontSize',FS-1);
title(ax4, 'Frame-wise SNR', 'FontWeight','normal');
panelLabel(ax4, 'd)', FONT, FS);

% ---------- 전체 스타일 통일 ----------
colormap(fig, COLORMAP_NAME);
allAx = findall(fig, 'Type','axes');
set(allAx, 'FontName',FONT, 'FontSize',FS, 'TickDir','out', ...
           'LineWidth',0.6, 'Layer','top', 'Box','on');

% =====================================================================
% [6] 출력 (600 dpi PNG + 벡터 PDF)
% =====================================================================
if EXPORT_PNG
    exportgraphics(fig, [OUT_BASENAME '.png'], 'Resolution', DPI);
    fprintf('>> 저장: %s.png (%d dpi)\n', OUT_BASENAME, DPI);
end
if EXPORT_PDF
    exportgraphics(fig, [OUT_BASENAME '.pdf'], 'ContentType','vector');
    fprintf('>> 저장: %s.pdf (vector)\n', OUT_BASENAME);
end

end % ===== main =====


% =====================================================================
% [서브함수] 등고선/이미지 맵 패널 그리기
% =====================================================================
function drawMap(ax, XI, YI, Z, cl, cbTicks, cbLabel, mapStyle, nLev, doLines, unitStr)
    % 컬러 범위 클리핑 (NaN은 비교 false -> 그대로 유지되어 공백 처리됨)
    Z(Z < cl(1)) = cl(1);
    Z(Z > cl(2)) = cl(2);

    hold(ax, 'on');
    if strcmpi(mapStyle, 'contourf')
        lev = linspace(cl(1), cl(2), nLev + 1);
        contourf(ax, XI, YI, Z, lev, 'LineStyle','none');
        if doLines
            contour(ax, XI, YI, Z, lev, ...
                    'LineColor',[0.40 0.40 0.40], 'LineWidth',0.25);
        end
    else
        % imagesc 모드: NaN(마스크)은 AlphaData로 투명 처리
        imagesc(ax, XI(1,:), YI(:,1), Z, 'AlphaData', ~isnan(Z));
    end

    set(ax, 'YDir','reverse');          % 이미지 좌표계 (y 아래 방향)
    axis(ax, 'image');
    xlim(ax, [XI(1,1) XI(1,end)]);
    ylim(ax, [YI(1,1) YI(end,1)]);
    clim(ax, cl);

    cb = colorbar(ax, 'southoutside');  % Harzallah 스타일 수평 컬러바
    cb.Ticks         = cbTicks;
    cb.Label.String  = cbLabel;
    cb.TickDirection = 'out';
    cb.FontSize      = get(ax, 'FontSize');

    xlabel(ax, ['x [' unitStr ']']);
    ylabel(ax, ['y [' unitStr ']']);
end

% =====================================================================
% [서브함수] 이탤릭 패널 문자 (축 좌상단 외곽)
% =====================================================================
function panelLabel(ax, str, fontName, fs)
    text(ax, -0.14, 1.10, str, 'Units','normalized', ...
         'FontName',fontName, 'FontSize',fs+2, ...
         'FontWeight','bold', 'FontAngle','italic');
end
