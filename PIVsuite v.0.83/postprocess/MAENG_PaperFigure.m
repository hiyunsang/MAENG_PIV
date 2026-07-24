function MAENG_PaperFigure(pivData)
% MAENG_PaperFigure — 논문 Experimental Setup 검증용 4패널 Figure 한 방 생성
%
%   (a) 원본 이미지 + 스케일바   (b) 속도장 합성 이미지 (마스크 밖 = 원본 grayscale)
%   (c) 시간평균 SNR 맵          (d) SNR 그래프 (시퀀스: 프레임별 추이 / 페어: 분포)
%
%   ▶ F5(실행)만 눌러도 동작: 작업공간의 pivData 자동 로드
%   ▶ 페어(Nt=1)·시퀀스 데이터 모두 지원
%   ▶ (b)는 MAENG_VisualizePairFromSequence와 동일한 픽셀 해상도 합성 렌더링
%   ▶ SNR 기준: Keane & Adrian (1990), SNR > 1.5 → valid vector

  %% ==========================================================
  %% ⚙️ 사용자 설정
  %% ==========================================================
  RAW_FRAME    = 1;          % (a) 원본 이미지로 쓸 프레임 번호
  PIV_FRAME    = 1;          % (b) PIV 속도장으로 쓸 프레임 번호
  VEL_CLIM     = [0 2];      % (b) 속도 크기 컬러 범위 [px/frame]
  QUIVER_STEP  = 0;          % (b) 화살표 밀도: 격자 N칸마다 1개 (0 = 화살표 끔)
  QUIVER_SCALE = 3;          % (b) 화살표 길이 = 변위(px) x 배수
  SHOW_BOUNDARY = true;      % (b) 마스크 경계선 표시
  RAW_BRIGHTNESS = 1.1;      % (a) 원본 이미지 밝기 보정 (1.0 = 원본)
  RAW_CONTRAST   = 1.2;      % (a) 원본 이미지 대비 보정 (1.0 = 원본)
  BG_BRIGHTNESS  = 1.1;      % (b) 배경(마스크 밖) 밝기 보정
  BG_CONTRAST    = 1.2;      % (b) 배경(마스크 밖) 대비 보정

  SNR_THRESH   = 1.5;        % (c,d) Keane & Adrian 유효 기준
  SNR_CAP      = 20;         % SNR 상한 클립 (2차 피크 미검출 지점 포함) — 논문에 "clipped at 20" 명시
  SNR_SMOOTH   = 1.5;        % (c) SNR 맵 공간 스무딩 강도 (0 = 끔)

  MM_PER_PX    = 0.00234;    % 1픽셀당 물리 길이 [mm/px] — 스케일바용
  SCALE_BAR_UM = 200;        % (a)에 그릴 스케일바 길이 [µm] (0 = 안 그림)

  IMG_PATH_MANUAL  = '';     % 원본 이미지 자동 검출 실패 시 수동 경로 지정
  MASK_PATH_MANUAL = '';     % 마스크 자동 검출 실패 시 수동 경로 지정

  SAVE_FIG     = true;                     % PNG(600dpi) + PDF(vector) 저장
  OUT_BASENAME = 'fig_piv_validation';     % 저장 파일 이름 (확장자 제외)

  %% ==========================================================
  %% 1) pivData 로드
  %% ==========================================================
  if nargin < 1 || isempty(pivData)
      if evalin('base', 'exist(''pivData'',''var'')')
          pivData = evalin('base', 'pivData');
          disp('>> 작업공간(base)의 pivData 를 불러왔습니다.');
      else
          [f, p] = uigetfile('*.mat', 'pivData 가 저장된 .mat 파일을 선택하세요');
          if isequal(f, 0), error('pivData 가 필요합니다. 실행을 취소합니다.'); end
          S = load(fullfile(p, f));
          if isfield(S, 'pivData'), pivData = S.pivData;
          else, fn = fieldnames(S); pivData = S.(fn{1}); end
      end
  end

  if ndims(pivData.U) < 3, Nt = 1; else, Nt = size(pivData.U, 3); end
  RAW_FRAME = max(1, min(RAW_FRAME, Nt));
  PIV_FRAME = max(1, min(PIV_FRAME, Nt));

  Xax = pivData.X(1,:);
  Yax = pivData.Y(:,1);

  %% ==========================================================
  %% 2) (a) 원본 이미지 로드 (imArray1 → imFilename → imagePath 순)
  %% ==========================================================
  [rawA, srcA] = local_loadRaw(pivData, RAW_FRAME, IMG_PATH_MANUAL);
  if isempty(rawA)
      warning('원본 이미지를 찾지 못했습니다. IMG_PATH_MANUAL 을 설정하세요. (a),(b) 배경은 회색으로 대체합니다.');
  else
      fprintf('>> (a) 원본 이미지: %s\n', srcA);
  end

  %% ==========================================================
  %% 3) (b) 속도장 합성 이미지 (VisualizePairFromSequence 방식)
  %% ==========================================================
  [rawB, srcB] = local_loadRaw(pivData, PIV_FRAME, IMG_PATH_MANUAL);
  if ~isempty(rawB), fprintf('>> (b) 배경 이미지: %s\n', srcB); end

  % 이미지 크기 결정 (배경 → 마스크 → 격자 범위 순으로 추정)
  if ~isempty(rawB)
      imH = size(rawB,1);  imW = size(rawB,2);
  elseif ~isempty(rawA)
      imH = size(rawA,1);  imW = size(rawA,2);
  else
      imW = ceil(max(pivData.X(:)) + double(pivData.iaStepX)/2);
      imH = ceil(max(pivData.Y(:)) + double(pivData.iaStepY)/2);
  end

  bgA = local_normalizeBg(rawA, imH, imW, RAW_BRIGHTNESS, RAW_CONTRAST);
  bgB = local_normalizeBg(rawB, imH, imW, BG_BRIGHTNESS, BG_CONTRAST);

  % 마스크 (없으면 전체 유효 = 전체에 속도장 표시)
  maskBin = local_resolveMask(pivData, PIV_FRAME, imH, imW, MASK_PATH_MANUAL);

  % 속도장 슬라이스 → NaN 외삽 → 픽셀 해상도 업샘플
  Uk = double(pivData.U(:,:,PIV_FRAME));
  Vk = double(pivData.V(:,:,PIV_FRAME));
  if any(isnan(Uk(:)))
      Uf = inpaint_nans(Uk, 2);
      Vf = inpaint_nans(Vk, 2);
  else
      Uf = Uk;  Vf = Vk;
  end
  [Xpix, Ypix] = meshgrid(1:imW, 1:imH);
  F_U = griddedInterpolant({double(Yax), double(Xax)}, Uf, 'cubic', 'linear');
  F_V = griddedInterpolant({double(Yax), double(Xax)}, Vf, 'cubic', 'linear');
  Umag_pix = hypot(F_U(Ypix, Xpix), F_V(Ypix, Xpix));

  % turbo 컬러맵 (구버전 호환)
  nColors = 256;
  try
      velCmap = turbo(nColors);
  catch
      keyT = [0.18995 0.07176 0.23217; 0.27149 0.41614 0.81616; 0.13990 0.71880 0.84314; ...
              0.16444 0.89409 0.55834; 0.71776 0.95977 0.20755; 0.97819 0.79410 0.20194; ...
              0.95201 0.36915 0.10882; 0.47960 0.01583 0.01055];
      tt = linspace(0,1,size(keyT,1)).';  tq = linspace(0,1,nColors).';
      velCmap = max(0, min(1, [interp1(tt,keyT(:,1),tq,'pchip'), ...
                               interp1(tt,keyT(:,2),tq,'pchip'), ...
                               interp1(tt,keyT(:,3),tq,'pchip')]));
  end

  % RGB 합성: 마스크 안 = 속도 컬러, 마스크 밖 = 원본 grayscale
  vNorm = (Umag_pix - VEL_CLIM(1)) / max(VEL_CLIM(2) - VEL_CLIM(1), eps);
  cIdx  = max(1, min(nColors, round(max(0, min(1, vNorm)) * (nColors-1)) + 1));
  rgbB  = zeros(imH, imW, 3);
  for ch = 1:3
      velC = reshape(velCmap(cIdx(:), ch), imH, imW);
      rgbB(:,:,ch) = velC .* maskBin + bgB .* (~maskBin);
  end
  rgbB = max(0, min(1, rgbB));

  %% ==========================================================
  %% 4) (c,d) SNR = 1차/2차 피크 비 (Keane & Adrian detectability)
  %% ==========================================================
  % 2차 피크가 검출되지 않은 지점(NaN/극소)은 "매우 깨끗한 상관"이라는 뜻 —
  % 분모 바닥값으로 나누면 SNR이 수백~수천으로 폭발하므로 상한(SNR_CAP)으로 클립.
  cc1 = pivData.ccPeak;
  cc2 = pivData.ccPeakSecondary;
  snrAll = cc1 ./ cc2;
  snrAll(~isnan(cc1) & (isnan(cc2) | cc2 < 1e-3)) = SNR_CAP;   % 2차 피크 미검출 → 상한
  snrAll = min(snrAll, SNR_CAP);                               % 전체 상한 클립
  snrAll(snrAll < 0) = 0;
  snrAll(isnan(cc1)) = NaN;                                    % 1차 피크 없음(마스크 등) = 무효

  snrMean = mean(snrAll, 3, 'omitnan');
  nanMask = all(isnan(cc1), 3);
  if SNR_SMOOTH > 0
      try, snrMean = smoothn(snrMean, SNR_SMOOTH); catch, end   % core 미등록 시 생략
  end
  snrMean(nanMask) = NaN;

  validYield = 100 * nnz(snrAll > SNR_THRESH) / max(1, nnz(~isnan(snrAll)));

  vSNR = snrMean(~isnan(snrMean));
  snrClim = [min(prctile(vSNR,1), 1), prctile(vSNR, 99)];
  if diff(snrClim) < 0.5, snrClim = mean(snrClim) + [-0.5 0.5]; end

  keyC = [0.020 0.140 0.290; 0.050 0.280 0.470; 0.130 0.450 0.590; ...
          0.310 0.610 0.670; 0.500 0.760 0.760; 0.660 0.850 0.815; 0.780 0.905 0.855];
  ts = linspace(0,1,size(keyC,1)).';  tq = linspace(0,1,256).';
  qcmap = [interp1(ts,keyC(:,1),tq), interp1(ts,keyC(:,2),tq), interp1(ts,keyC(:,3),tq)];

  %% ==========================================================
  %% 5) Figure (두 단 폭 18 cm x 2행)
  %% ==========================================================
  fig = figure('Name', 'PIV validation (paper figure)', 'Color', 'w', ...
               'Units', 'centimeters', 'Position', [2 2 18 14.5]);
  tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

  % ---------------- (a) 원본 이미지 ----------------
  ax1 = nexttile;
  image(ax1, [1 imW], [1 imH], repmat(bgA, [1 1 3]));   % grayscale → RGB로 표시
  hold(ax1, 'on');
  if SCALE_BAR_UM > 0 && MM_PER_PX > 0
      barPx = (SCALE_BAR_UM/1000) / MM_PER_PX;
      x0 = imW*0.06;  y0 = imH*0.92;
      plot(ax1, [x0, x0+barPx], [y0 y0], 'w-', 'LineWidth', 3);
      text(ax1, x0+barPx/2, y0-imH*0.045, sprintf('%d \\mum', SCALE_BAR_UM), ...
           'Color','w','FontSize',9,'FontName','Arial','HorizontalAlignment','center');
  end
  hold(ax1, 'off');
  local_styleAxes(ax1, imW, imH);
  title(ax1, sprintf('(a) Raw image (frame %d)', RAW_FRAME), 'FontWeight','normal','FontSize',11);
  xlabel(ax1,'x [px]'); ylabel(ax1,'y [px]');

  % ---------------- (b) 속도장 합성 이미지 ----------------
  ax2 = nexttile;
  image(ax2, [1 imW], [1 imH], rgbB);
  hold(ax2, 'on');
  if SHOW_BOUNDARY && any(~maskBin(:))
      try
          B = bwboundaries(maskBin, 8, 'noholes');
          for k = 1:length(B)
              plot(ax2, B{k}(:,2), B{k}(:,1), 'k-', 'LineWidth', 1.2);
          end
      catch
      end
  end
  if QUIVER_STEP > 0
      ii = 1:QUIVER_STEP:size(pivData.X,1);
      jj = 1:QUIVER_STEP:size(pivData.X,2);
      quiver(ax2, pivData.X(ii,jj), pivData.Y(ii,jj), ...
             QUIVER_SCALE*Uk(ii,jj), QUIVER_SCALE*Vk(ii,jj), 0, 'k');
  end
  hold(ax2, 'off');
  local_styleAxes(ax2, imW, imH);
  colormap(ax2, velCmap);
  try, clim(ax2, VEL_CLIM); catch, caxis(ax2, VEL_CLIM); end
  cb2 = colorbar(ax2); cb2.Label.String = '|V| [px/frame]'; cb2.LineWidth = 0.8;
  title(ax2, sprintf('(b) PIV velocity field (frame %d)', PIV_FRAME), 'FontWeight','normal','FontSize',11);
  xlabel(ax2,'x [px]'); ylabel(ax2,'y [px]');

  % ---------------- (c) 시간평균 SNR 맵 ----------------
  ax3 = nexttile;
  hSnr = imagesc(ax3, Xax, Yax, snrMean, snrClim);
  set(hSnr, 'AlphaData', ~isnan(snrMean));
  colormap(ax3, qcmap);
  local_styleAxes(ax3, imW, imH);
  cb3 = colorbar(ax3); cb3.Label.String = 'SNR'; cb3.LineWidth = 0.8;
  cand = [1, SNR_THRESH, 2, 5, 10, 15, 20];
  ticksIn = unique([snrClim(1), cand(cand>=snrClim(1) & cand<=snrClim(2)), snrClim(2)]);
  cb3.Ticks = ticksIn;
  lbls = arrayfun(@(v) sprintf('%.1f', v), ticksIn, 'UniformOutput', false);
  lbls(abs(ticksIn-SNR_THRESH) < 1e-9) = {sprintf('%.1f (K&A)', SNR_THRESH)};
  cb3.TickLabels = lbls;
  if Nt > 1, tstr = '(c) Time-averaged SNR map';
  else,      tstr = '(c) SNR map';
  end
  title(ax3, tstr, 'FontWeight','normal','FontSize',11);
  xlabel(ax3,'x [px]'); ylabel(ax3,'y [px]');

  % ---------------- (d) SNR 그래프 ----------------
  ax4 = nexttile;
  hold(ax4, 'on'); grid(ax4, 'on'); box(ax4, 'on');
  if Nt > 1
      % 시퀀스: 프레임별 median/mean 추이
      snrStat = zeros(Nt, 2);
      for kt = 1:Nt
          sn = snrAll(:,:,kt);
          snrStat(kt,1) = median(sn(:), 'omitnan');
          snrStat(kt,2) = mean(  sn(:), 'omitnan');
      end
      movWin = max(3, round(Nt*0.05));
      snrStatS = movmean(snrStat, movWin, 1, 'omitnan');
      frames = 1:Nt;
      plot(ax4, frames, snrStat(:,1), '-', 'Color',[0.75 0.80 0.85], 'LineWidth',0.8);
      hMed = plot(ax4, frames, snrStatS(:,1), '-', 'Color',[0.10 0.30 0.55], 'LineWidth',2.0);
      hAvg = plot(ax4, frames, snrStatS(:,2), '-', 'Color',[0.65 0.20 0.25], 'LineWidth',2.0);
      hThr = plot(ax4, [1 Nt], SNR_THRESH*[1 1], '--', 'Color',[0.3 0.3 0.3], 'LineWidth',1.0);
      xlim(ax4, [1 Nt]);
      ylim(ax4, [1, max([snrStat(:); 2])*1.05]);
      xlabel(ax4,'Frame index'); ylabel(ax4,'SNR');
      legend(ax4, [hMed hAvg hThr], {'median','mean','K&A threshold'}, ...
             'Location','best','FontSize',9,'Box','off');
      title(ax4, '(d) Temporal evolution of SNR', 'FontWeight','normal','FontSize',11);
  else
      % 페어: SNR 분포 히스토그램
      sn = snrAll(~isnan(snrAll));
      histogram(ax4, sn, 40, 'FaceColor',[0.13 0.45 0.59], 'EdgeColor','none');
      yl = ylim(ax4);
      plot(ax4, SNR_THRESH*[1 1], yl, '--', 'Color',[0.3 0.3 0.3], 'LineWidth',1.2);
      text(ax4, SNR_THRESH, yl(2)*0.95, sprintf('  %.1f (K&A)', SNR_THRESH), ...
           'FontSize',9, 'Color',[0.3 0.3 0.3]);
      xlabel(ax4,'SNR'); ylabel(ax4,'Count');
      title(ax4, '(d) SNR distribution', 'FontWeight','normal','FontSize',11);
  end
  text(ax4, 0.98, 0.05, sprintf('valid yield (SNR>%.1f): %.1f %%', SNR_THRESH, validYield), ...
       'Units','normalized', 'HorizontalAlignment','right', 'FontSize',9, 'FontName','Arial');
  set(ax4, 'FontName','Arial','FontSize',10,'LineWidth',0.8,'TickDir','out');
  hold(ax4, 'off');

  %% ==========================================================
  %% 6) 요약 출력 + 저장
  %% ==========================================================
  fprintf('\n===== PIV 품질 요약 =====\n');
  fprintf('SNR: median = %.2f, mean = %.2f  (프레임 %d개 전체, 상한 %g 클립)\n', ...
          median(snrAll(:),'omitnan'), mean(snrAll(:),'omitnan'), Nt, SNR_CAP);
  fprintf('유효 벡터 수율 (SNR > %.1f): %.1f %%\n', SNR_THRESH, validYield);

  if SAVE_FIG
      exportgraphics(fig, [OUT_BASENAME '.png'], 'Resolution', 600);
      exportgraphics(fig, [OUT_BASENAME '.pdf'], 'ContentType', 'vector');
      fprintf('저장 완료: %s.png (600dpi), %s.pdf (vector)\n', OUT_BASENAME, OUT_BASENAME);
  end
end


%% ==========================================================
%% 🛠 원본 이미지 로드 (imArray1 → imFilename1/2 → imagePath 순)
%% ==========================================================
function [img, src] = local_loadRaw(pivData, frame, manualPath)
  img = [];  src = '';

  % 0) 수동 지정 경로 최우선
  if ~isempty(manualPath) && exist(manualPath, 'file')
      img = imread(manualPath);  src = ['수동: ' manualPath];
  end

  % 1) 엔진이 저장한 이미지 배열 (경로 문제와 무관하게 항상 존재하면 사용)
  if isempty(img) && isfield(pivData, 'imArray1') && ~isempty(pivData.imArray1)
      arr = pivData.imArray1;
      if ndims(arr) == 3 && size(arr,3) >= frame
          img = double(arr(:,:,frame));  src = 'pivData.imArray1';
      elseif ismatrix(arr)
          img = double(arr);             src = 'pivData.imArray1';
      end
  end

  % 2) 저장된 파일 경로
  if isempty(img)
      for f = {'imFilename1', 'imFilename2'}
          if ~isfield(pivData, f{1}), continue; end
          val = pivData.(f{1});
          candidate = '';
          if iscell(val) && ~isempty(val)
              candidate = char(val{min(frame, numel(val))});
          elseif ischar(val) || (isstring(val) && isscalar(val))
              candidate = char(val);
          end
          if ~isempty(candidate) && exist(candidate, 'file')
              img = imread(candidate);  src = candidate;  break;
          end
      end
  end

  % 3) imagePath 폴더 스캔
  if isempty(img) && isfield(pivData, 'imagePath') && exist(pivData.imagePath, 'dir')
      for ext = {'*.tif', '*.tiff', '*.png', '*.bmp', '*.jpg'}
          D = dir(fullfile(pivData.imagePath, ext{1}));
          if ~isempty(D)
              [~, si] = sort({D.name});
              idx = min(frame, numel(D));
              fn = fullfile(pivData.imagePath, D(si(idx)).name);
              img = imread(fn);  src = fn;  break;
          end
      end
  end

  if ~isempty(img) && size(img,3) > 1
      img = mean(double(img), 3);        % RGB → grayscale
  end
  img = double(img);
end


%% ==========================================================
%% 🛠 배경 정규화 (0~1 grayscale + 밝기/대비 보정)
%% ==========================================================
function bg = local_normalizeBg(raw, imH, imW, brightness, contrast)
  if isempty(raw)
      bg = 0.78 * ones(imH, imW);        % 이미지 없으면 회색
      return;
  end
  bg = double(raw);
  if size(bg,1) ~= imH || size(bg,2) ~= imW
      bg = imresize(bg, [imH imW]);
  end
  bg = bg / max(bg(:));
  bg = (bg - 0.5) * contrast + 0.5;
  bg = bg * brightness;
  bg = max(0, min(1, bg));
end


%% ==========================================================
%% 🛠 마스크 해상 (imMaskArray1 → imMaskFilename1, 없으면 전체 유효)
%% ==========================================================
function mb = local_resolveMask(pivData, frame, imH, imW, manualPath)
  m = [];
  if ~isempty(manualPath) && exist(manualPath, 'file')
      m = imread(manualPath);
  elseif isfield(pivData, 'imMaskArray1') && ~isempty(pivData.imMaskArray1)
      m = pivData.imMaskArray1;
      if ndims(m) == 3 && size(m,3) >= frame, m = m(:,:,frame); end
  elseif isfield(pivData, 'imMaskFilename1') && ~isempty(pivData.imMaskFilename1)
      val = pivData.imMaskFilename1;
      candidate = '';
      if iscell(val) && ~isempty(val)
          candidate = char(val{min(frame, numel(val))});
      elseif ischar(val) || (isstring(val) && isscalar(val))
          candidate = char(val);
      end
      if ~isempty(candidate) && exist(candidate, 'file')
          m = imread(candidate);
      end
  end

  if isempty(m)
      mb = true(imH, imW);               % 마스크 없음(마스크 OFF) = 전체에 속도장 표시
      return;
  end
  if size(m,3) > 1, m = m(:,:,1); end
  mb = double(m) > 0;
  if size(mb,1) ~= imH || size(mb,2) ~= imW
      mb = imresize(mb, [imH imW], 'nearest');
  end
end


%% ==========================================================
%% 🛠 공통 축 스타일 (이미지 패널)
%% ==========================================================
function local_styleAxes(ax, imW, imH)
  axis(ax, 'image');
  axis(ax, [1 imW 1 imH]);
  set(ax, 'YDir','reverse', 'Color',[0.85 0.85 0.85], ...
      'FontName','Arial', 'FontSize',10, 'LineWidth',0.8, 'TickDir','out', ...
      'Box','on', 'Layer','top');
end
