function eff = MAENG_EffStrain(pivData)
% MAENG_EffStrain — 두 프레임의 순간 유효 변형률률 계산 · 비교 시각화
%
%   ▶ F5(실행)만 눌러도 동작: 작업공간의 pivData 자동 로드 → 없으면 .mat 파일 선택
%   ▶ 프레임 두 개를 지정하면 각각의 순간 변형률을 나란히 표시

  %% ==========================================================
  %% ⚙️ 사용자 설정
  %% ==========================================================
  mmPerPx          = 0.00234;   % 1픽셀당 물리 길이 [mm/px]
  VIS_COLORMAP     = 'jet';
  VIS_TRANSPARENCY = 1.0;
  CONTOUR_LEVELS   = 80;
  SMOOTH_SIGMA     = 0.5;       % 속도장 가우시안 스무딩 σ [격자 간격 단위, 0 = 끔]
  OUTLIER_THRESH   = 2.0;       % 정규화 중앙값 검정 임계값 (작을수록 엄격, 0 = 끔)

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
          fprintf('>> 파일에서 pivData 를 불러왔습니다: %s\n', f);
      end
  end

  %% ==========================================================
  %% 2) 차원 확인 및 물리 그리드 생성
  %% ==========================================================
  if ndims(pivData.U) < 3
      [Ny, Nx] = size(pivData.U); Nt = 1;
  else
      [Ny, Nx, Nt] = size(pivData.U);
  end

  X_mm = double(pivData.X) * mmPerPx;
  Y_mm = double(pivData.Y) * mmPerPx;
  dx   = double(pivData.iaStepX) * mmPerPx;
  dy   = double(pivData.iaStepY) * mmPerPx;

  x_world = [min(X_mm(:)) - dx/2, max(X_mm(:)) + dx/2];
  y_world = [min(Y_mm(:)) - dy/2, max(Y_mm(:)) + dy/2];

  %% ==========================================================
  %% 3) 프레임 두 개 지정
  %% ==========================================================
  ans_dialog = inputdlg( ...
      {'프레임 A:', sprintf('프레임 B  (최대 %d):', Nt)}, ...
      '비교할 프레임 두 개 입력', 1, {'1', num2str(Nt)});

  if isempty(ans_dialog), disp('취소됨.'); eff = []; return; end

  frameA = round(str2double(ans_dialog{1}));
  frameB = round(str2double(ans_dialog{2}));
  frameA = max(1, min(frameA, Nt));
  frameB = max(1, min(frameB, Nt));
  fprintf('>> 선택 프레임: A=%d, B=%d\n', frameA, frameB);

  %% ==========================================================
  %% 4) 마스크 · 변형률 계산
  %% ==========================================================
  trueMask = local_computePermanentMask(pivData, Ny, Nx, Nt);
  fileList = local_buildFileList(pivData, Nt);

  EpsA = local_computeFrameStrain(pivData, frameA, mmPerPx, X_mm, Y_mm, dx, dy, trueMask, SMOOTH_SIGMA, OUTLIER_THRESH);
  EpsB = local_computeFrameStrain(pivData, frameB, mmPerPx, X_mm, Y_mm, dx, dy, trueMask, SMOOTH_SIGMA, OUTLIER_THRESH);

  % 컬러바 범위: 두 프레임 데이터 합산 기준 자동 결정
  all_vals = [EpsA(isfinite(EpsA)); EpsB(isfinite(EpsB))];
  clim_max = max(prctile(all_vals, 99), 0.01);
  STRAIN_CLIM = [0, clim_max];
  fprintf('>> 컬러바 범위 자동 설정: [0  %.3f]\n', clim_max);

  eff.mmPerPx     = mmPerPx;
  eff.frameA      = frameA;
  eff.frameB      = frameB;
  eff.clim        = STRAIN_CLIM;
  eff.epsA        = EpsA;
  eff.epsB        = EpsB;
  eff.X_mm        = X_mm;
  eff.Y_mm        = Y_mm;

  %% ==========================================================
  %% 🎨 나란히 비교 시각화
  %% ==========================================================
  bgA = local_loadBgImage(fileList, frameA);
  bgB = local_loadBgImage(fileList, frameB);

  fig = figure('Name', sprintf('Instantaneous Strain  A=%d  B=%d', frameA, frameB), ...
               'Color', 'w', 'Position', [80 100 1400 620]);

  ax1 = subplot(1, 2, 1, 'Parent', fig);
  local_drawStrain(ax1, bgA, X_mm, Y_mm, EpsA, x_world, y_world, ...
                   CONTOUR_LEVELS, VIS_TRANSPARENCY, VIS_COLORMAP, STRAIN_CLIM);
  cb1 = colorbar(ax1); local_styleColorbar(cb1, STRAIN_CLIM);
  xlabel(ax1, 'x [mm]', 'FontSize', 12); ylabel(ax1, 'y [mm]', 'FontSize', 12);
  title(ax1, sprintf('순간 \\epsilon_{eff}  (Frame %d)', frameA), 'FontSize', 13);

  ax2 = subplot(1, 2, 2, 'Parent', fig);
  local_drawStrain(ax2, bgB, X_mm, Y_mm, EpsB, x_world, y_world, ...
                   CONTOUR_LEVELS, VIS_TRANSPARENCY, VIS_COLORMAP, STRAIN_CLIM);
  cb2 = colorbar(ax2); local_styleColorbar(cb2, STRAIN_CLIM);
  xlabel(ax2, 'x [mm]', 'FontSize', 12); ylabel(ax2, 'y [mm]', 'FontSize', 12);
  title(ax2, sprintf('순간 \\epsilon_{eff}  (Frame %d)', frameB), 'FontSize', 13);
end


%% ==========================================================
%% 🛠 단일 프레임 순간 유효 변형률 계산
%% ==========================================================
function Eps2D = local_computeFrameStrain(pivData, frame, mmPerPx, X_mm, Y_mm, dx, dy, trueMask, smoothSigma, outlierThresh)
  Uk = double(pivData.U(:,:,frame)) * mmPerPx;
  Vk = double(pivData.V(:,:,frame)) * mmPerPx;

  % 불량 벡터 검출 (정규화 중앙값 검정) — 노이즈를 스무딩 전에 원천 제거
  if outlierThresh > 0
      eps0 = 0.1 * mmPerPx;   % 서브픽셀 상관 노이즈 수준 (~0.1 px)
      bad  = local_normMedianTest(Uk, outlierThresh, eps0) | ...
             local_normMedianTest(Vk, outlierThresh, eps0);
      bad  = bad & ~trueMask;
      if any(bad(:))
          Uk(bad) = NaN;  Vk(bad) = NaN;
          fprintf('>> Frame %d: 불량 벡터 %d개 검출·제거 (중앙값 검정)\n', frame, nnz(bad));
      end
  end

  % 일시적 결측(상관 실패 등)은 속도를 보간해서 채움 — 영구 마스크(공구 영역 등)는 유지
  nHoles = nnz(isnan(Uk) & ~trueMask);
  if nHoles > 0
      Uk = local_fillHoles(Uk, X_mm, Y_mm, trueMask);
      Vk = local_fillHoles(Vk, X_mm, Y_mm, trueMask);
      fprintf('>> Frame %d: 결측 벡터 %d개를 보간으로 채움\n', frame, nHoles);
  end

  % 미분 전 속도장 스무딩 — 미분에 의한 노이즈 증폭 억제
  if smoothSigma > 0
      Uk = local_nanGaussSmooth(Uk, smoothSigma);
      Vk = local_nanGaussSmooth(Vk, smoothSigma);
  end

  [dUdx, dUdy] = local_nanGradient(Uk, dx, dy);
  [dVdx, dVdy] = local_nanGradient(Vk, dx, dy);

  eps_xx = dUdx;
  eps_yy = dVdy;
  eps_xy = 0.5 * (dUdy + dVdx);
  Eps2D  = sqrt((2/3) * (eps_xx.^2 + eps_yy.^2 + 2*eps_xy.^2));

  Eps2D(trueMask) = NaN;
end


%% ==========================================================
%% 🛠 정규화 중앙값 검정 (Westerweel & Scarano, 2005)
%% ==========================================================
function bad = local_normMedianTest(F, thresh, eps0)
  [Ny, Nx] = size(F);
  bad = false(Ny, Nx);
  for i = 1:Ny
      for j = 1:Nx
          if isnan(F(i,j)), continue; end
          i0 = max(1, i-1); i1 = min(Ny, i+1);
          j0 = max(1, j-1); j1 = min(Nx, j+1);
          nb = F(i0:i1, j0:j1);
          nb(i-i0+1, j-j0+1) = NaN;          % 중심점 제외
          nb = nb(~isnan(nb));
          if numel(nb) < 3, continue; end     % 이웃이 부족하면 판정 보류
          med  = median(nb);
          resm = median(abs(nb - med));       % 이웃 잔차의 중앙값
          if abs(F(i,j) - med) / (resm + eps0) > thresh
              bad(i,j) = true;
          end
      end
  end
end


%% ==========================================================
%% 🛠 속도 필드 가우시안 스무딩 (NaN 인지형)
%% ==========================================================
function Fs = local_nanGaussSmooth(F, sigma)
% NaN 영역을 침범하지 않는 가우시안 스무딩 (정규화 컨볼루션)
  r = max(1, ceil(3 * sigma));
  g = exp(-((-r:r).^2) / (2 * sigma^2));
  K = g' * g;
  K = K / sum(K(:));

  valid = ~isnan(F);
  F0 = F;  F0(~valid) = 0;
  num = conv2(F0, K, 'same');
  den = conv2(double(valid), K, 'same');
  Fs = num ./ den;
  Fs(~valid) = NaN;
end


%% ==========================================================
%% 🛠 속도 필드 결측 보간 (영구 마스크 제외)
%% ==========================================================
function F = local_fillHoles(F, X_mm, Y_mm, trueMask)
  valid = ~isnan(F);
  holes = ~valid & ~trueMask;
  if ~any(holes(:)) || nnz(valid) < 4, return; end
  Fi = scatteredInterpolant(X_mm(valid), Y_mm(valid), F(valid), 'natural', 'nearest');
  F(holes) = Fi(X_mm(holes), Y_mm(holes));
end


%% ==========================================================
%% 🛠 결측치 인지형 편측 미분
%% ==========================================================
function [dFdx, dFdy] = local_nanGradient(F, dx, dy)
  [Ny, Nx] = size(F);
  dFdx = nan(Ny, Nx);
  dFdy = nan(Ny, Nx);
  for i = 1:Ny
      for j = 1:Nx
          if isnan(F(i,j)), continue; end

          has_left  = (j > 1)  && ~isnan(F(i, j-1));
          has_right = (j < Nx) && ~isnan(F(i, j+1));
          if has_left && has_right
              dFdx(i,j) = (F(i, j+1) - F(i, j-1)) / (2 * dx);
          elseif has_left
              dFdx(i,j) = (F(i, j) - F(i, j-1)) / dx;
          elseif has_right
              dFdx(i,j) = (F(i, j+1) - F(i, j)) / dx;
          end

          has_up   = (i > 1)  && ~isnan(F(i-1, j));
          has_down = (i < Ny) && ~isnan(F(i+1, j));
          if has_up && has_down
              dFdy(i,j) = (F(i+1, j) - F(i-1, j)) / (2 * dy);
          elseif has_up
              dFdy(i,j) = (F(i, j) - F(i-1, j)) / dy;
          elseif has_down
              dFdy(i,j) = (F(i+1, j) - F(i, j)) / dy;
          end
      end
  end
end


%% ==========================================================
%% 🛠 영구 마스크
%% ==========================================================
function tm = local_computePermanentMask(pivData, Ny, Nx, Nt)
  tm = true(Ny, Nx);
  for k = 1:Nt
      Uk = double(pivData.U(:,:,k));
      Vk = double(pivData.V(:,:,k));
      tm = tm & ((Uk == 0 & Vk == 0) | isnan(Uk));
  end
end


%% ==========================================================
%% 🛠 배경 이미지 파일 목록
%% ==========================================================
function fl = local_buildFileList(pivData, Nt)
  fl = {};
  for f = {'imFilename2', 'imFilename1'}
      fn = f{1};
      if isfield(pivData, fn)
          val = pivData.(fn);
          if iscell(val) && ~isempty(val)
              fl = val(:); return;
          elseif (ischar(val) || isstring(val)) && exist(char(val), 'file')
              fl = repmat({char(val)}, Nt, 1); return;
          end
      end
  end
  if isfield(pivData, 'imagePath') && exist(pivData.imagePath, 'dir')
      for ext = {'*.png', '*.bmp', '*.tif', '*.tiff', '*.jpg'}
          D = dir(fullfile(pivData.imagePath, ext{1}));
          if ~isempty(D)
              [~, si] = sort({D.name});
              fl = fullfile(pivData.imagePath, {D(si).name})';
              return;
          end
      end
  end
end


%% ==========================================================
%% 🛠 배경 이미지 로드
%% ==========================================================
function img = local_loadBgImage(fileList, frame)
  img = [];
  if isempty(fileList), return; end
  idx = min(max(frame, 1), numel(fileList));
  fn  = fileList{idx};
  if (ischar(fn) || isstring(fn)) && exist(char(fn), 'file')
      try
          img = imread(char(fn));
          if size(img, 3) == 1, img = cat(3, img, img, img); end
      catch
          img = [];
      end
  end
end


%% ==========================================================
%% 🛠 변형률 필드 그리기
%% ==========================================================
function local_drawStrain(ax, bg, X_mm, Y_mm, Eps2D, x_world, y_world, levels, alphaVal, cmap, climv)
  cla(ax);
  hold(ax, 'on');

  if ~isempty(bg)
      image('Parent', ax, 'XData', x_world, 'YData', y_world, 'CData', bg);
  end
  set(ax, 'YDir', 'reverse');

  lv = linspace(climv(1), climv(2), levels);
  [~, hC] = contourf(ax, X_mm, Y_mm, Eps2D, lv, 'LineStyle', 'none');
  try, alpha(hC, alphaVal); catch, end

  daspect(ax, [1 1 1]);
  box(ax, 'on');
  colormap(ax, cmap);
  caxis(ax, climv);
  hold(ax, 'off');
end


%% ==========================================================
%% 🛠 컬러바 스타일
%% ==========================================================
function local_styleColorbar(cb, climv)
  cb.Limits = climv;
  cb.Ticks  = linspace(climv(1), climv(2), 5);
  ylabel(cb, '$\epsilon_{eff}$', 'Interpreter', 'latex', 'FontSize', 14);
end
