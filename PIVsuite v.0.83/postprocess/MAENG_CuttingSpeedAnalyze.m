function [cutStat] = MAENG_CuttingSpeedAnalyze(pivData, varargin)
% MAENG_CuttingSpeedAnalyze - 직교절삭(Orthogonal Cutting) PIV 결과에서
%   공작물(=수평으로 흐르는) 벡터만 선별하여 절삭속도(m/min)를 계산합니다.
%
% [실행 방법] 에디터에서 ▶ 실행 버튼만 누르면 끝
%   - 입력 없이 호출되면 base 워크스페이스에서 'pivData'를 자동으로 가져옵니다.
%   - 결과는 명령창에 m/min 단위로 표시되고, 'cutStat' 구조체로도 저장됩니다.
%
% =========================================================================
% [필수 설정 1] 광학계/카메라 보정값
% -------------------------------------------------------------------------
PIXEL_SIZE_MM_PER_PX = 0.00234;     % 1픽셀이 실제 몇 mm인가 (예: 10 um/px)
DT_S_PER_FRAME       = 1/2000;   % 프레임 간격(초). 1/fps
% =========================================================================
% [필수 설정 2] 공작물(수평 흐름) 판정 임계값
% -------------------------------------------------------------------------
%   ROI 안에 공작물 외 영역(자유면, 칩, 전단대 등)이 일부 섞여도
%   "수평으로 흐르는 벡터"만 골라내기 위한 필터.
%
%   FILTER_MODE = 'ratio'  : |V|/|U| < VU_RATIO_MAX 인 점만 사용 (기본·권장)
%   FILTER_MODE = 'abs'    : |V| < V_MAX_ABS (px/frame) 인 점만 사용
%   FILTER_MODE = 'none'   : 필터링 없이 ROI 내 전부 사용 (구버전 동작)
% -------------------------------------------------------------------------
FILTER_MODE   = 'ratio';
VU_RATIO_MAX  = 0.20;            % |V|가 |U|의 20% 미만이면 "수평"으로 판정
V_MAX_ABS     = 0.5;             % 'abs' 모드 전용 (px/frame)
U_MIN_PX      = 0.3;             % |U|가 이보다 작으면 잡음으로 보고 제외 (px/frame)
% =========================================================================
%
% [선택 옵션 - Name/Value]
%   'roi'         [xMin xMax yMin yMax] (px). 미지정 시 좌측 1/2 x 하단 1/2 자동
%   'show'        true이면 첫 프레임 위에 ROI와 채택된 점을 시각화
%   'filterMode'  'ratio' / 'abs' / 'none' (위 상수 덮어쓰기)
%   'vuRatioMax'  ratio 모드 임계값 (위 상수 덮어쓰기)
%   'pixelSize'   mm/px 보정값 (위 PIXEL_SIZE_MM_PER_PX 덮어쓰기)
%   'dt'          s/frame 프레임 간격 (위 DT_S_PER_FRAME 덮어쓰기)
% =========================================================================

%% 0-A. 실행 버튼만 눌렀을 때(=인수 없음) base 워크스페이스에서 pivData 가져오기
if nargin < 1 || isempty(pivData)
    try
        pivData = evalin('base', 'pivData');
        fprintf('[MAENG_CuttingSpeedAnalyze] base 워크스페이스의 ''pivData''를 자동으로 불러왔습니다.\n');
    catch
        error('MAENG_CuttingSpeedAnalyze:noPivData', ...
            ['워크스페이스에 ''pivData'' 변수가 없습니다.\n', ...
             '   먼저 마스크 스크립트를 실행하여 pivData를 생성한 뒤\n', ...
             '   이 함수를 실행하거나, 명령창에서 MAENG_CuttingSpeedAnalyze(pivData) 형태로 호출하세요.']);
    end
end

%% 0-B. 입력 파라미터 파싱 -------------------------------------------------
p = inputParser;
addParameter(p, 'roi',         [],            @(x) isempty(x) || (isnumeric(x) && numel(x)==4));
addParameter(p, 'show',        false,         @islogical);
addParameter(p, 'filterMode',  FILTER_MODE,   @(s) ischar(s) || isstring(s));
addParameter(p, 'vuRatioMax',  VU_RATIO_MAX,  @(x) isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'pixelSize',   PIXEL_SIZE_MM_PER_PX, @(x) isnumeric(x) && isscalar(x) && x>0);
addParameter(p, 'dt',          DT_S_PER_FRAME,       @(x) isnumeric(x) && isscalar(x) && x>0);
parse(p, varargin{:});
opt = p.Results;
FILTER_MODE  = char(opt.filterMode);
VU_RATIO_MAX = opt.vuRatioMax;
PIXEL_SIZE_MM_PER_PX = opt.pixelSize;
DT_S_PER_FRAME       = opt.dt;

%% 1. pivData 유효성 검사 ---------------------------------------------------
if ~all(isfield(pivData, {'U','V','X','Y'}))
    error('MAENG_CuttingSpeedAnalyze:invalidInput', ...
          'pivData에 U/V/X/Y 필드가 없습니다. pivAnalyzeImageSequence 결과인지 확인하세요.');
end
U = pivData.U;
V = pivData.V;
X = pivData.X;
Y = pivData.Y;
if ndims(U) == 2
    U = reshape(U, size(U,1), size(U,2), 1);
    V = reshape(V, size(V,1), size(V,2), 1);
end
Nt = size(U,3);

%% 2. ROI 결정 -------------------------------------------------------------
xMinAll = min(X(:));   xMaxAll = max(X(:));
yMinAll = min(Y(:));   yMaxAll = max(Y(:));

if isempty(opt.roi)
    xMin = xMinAll;
    xMax = xMinAll + 0.5*(xMaxAll - xMinAll);
    yMin = yMinAll + 0.5*(yMaxAll - yMinAll);   % imread 좌표계: 아래가 Y 큼
    yMax = yMaxAll;
    fprintf('[MAENG_CuttingSpeedAnalyze] ROI 자동 설정 (좌측 1/2 x 하단 1/2).\n');
else
    xMin = opt.roi(1);  xMax = opt.roi(2);
    yMin = opt.roi(3);  yMax = opt.roi(4);
end
roi = [xMin xMax yMin yMax];

inROI = (X >= xMin) & (X <= xMax) & (Y >= yMin) & (Y <= yMax);
nPtsROI = nnz(inROI);
if nPtsROI == 0
    error('MAENG_CuttingSpeedAnalyze:emptyROI', ...
          '지정한 ROI 안에 PIV 벡터가 하나도 없습니다. roi 값을 확인하세요.');
end

%% 3. 단위 변환 계수: px/frame -> m/min ------------------------------------
scale   = PIXEL_SIZE_MM_PER_PX * (1/DT_S_PER_FRAME) * 60 / 1000;
unitStr = 'm/min';

%% 4. ROI + 수평흐름 필터 적용 → 통계 계산 --------------------------------
perFrameMean   = nan(Nt,1);
perFrameMax    = nan(Nt,1);
perFrameMin    = nan(Nt,1);
perFrameNused  = zeros(Nt,1);

acceptedMaskAccum = false(size(X));   % 시각화용: 한 번이라도 채택된 위치

for kt = 1:Nt
    Uk = U(:,:,kt);
    Vk = V(:,:,kt);

    % --- (1) 유효성: NaN 제외 + 잡음수준 |U| 제외
    validBase = ~isnan(Uk) & ~isnan(Vk) & (abs(Uk) >= U_MIN_PX);

    % --- (2) 수평흐름 판정 필터
    switch lower(FILTER_MODE)
        case 'ratio'
            % |V|/|U| < 임계비율  ->  거의 수평
            isHorizontal = abs(Vk) < VU_RATIO_MAX * abs(Uk);
        case 'abs'
            isHorizontal = abs(Vk) < V_MAX_ABS;
        case 'none'
            isHorizontal = true(size(Uk));
        otherwise
            error('MAENG_CuttingSpeedAnalyze:badFilterMode', ...
                  'FILTER_MODE는 ''ratio'', ''abs'', ''none'' 중 하나여야 합니다.');
    end

    % --- (3) 최종 선택 마스크: ROI ∩ 유효 ∩ 수평흐름
    selMask = inROI & validBase & isHorizontal;
    acceptedMaskAccum = acceptedMaskAccum | selMask;

    speedSel = abs(Uk(selMask));   % 절삭속도 = |U|
    perFrameNused(kt) = numel(speedSel);
    if isempty(speedSel)
        continue;
    end
    perFrameMean(kt) = mean(speedSel);
    perFrameMax(kt)  = max(speedSel);
    perFrameMin(kt)  = min(speedSel);
end

validF = ~isnan(perFrameMean);
if ~any(validF)
    error('MAENG_CuttingSpeedAnalyze:noHorizontalVecs', ...
        ['ROI 내에서 수평흐름 조건을 만족하는 벡터가 한 프레임도 없습니다.\n', ...
         '   - VU_RATIO_MAX(현재 %.2f)를 키우거나\n', ...
         '   - FILTER_MODE를 ''none''으로 두고 ROI를 더 좁혀보세요.'], VU_RATIO_MAX);
end

cutStat.maxSpeed   = max(perFrameMax(validF))   * scale;
cutStat.minSpeed   = min(perFrameMin(validF))   * scale;
cutStat.meanSpeed  = mean(perFrameMean(validF)) * scale;

nFirst = min(3, nnz(validF));
nLast  = min(3, nnz(validF));
idxAll = find(validF);
idxF3  = idxAll(1:nFirst);
idxL3  = idxAll(end-nLast+1:end);
cutStat.meanFirst3 = mean(perFrameMean(idxF3)) * scale;
cutStat.meanLast3  = mean(perFrameMean(idxL3)) * scale;

cutStat.perFrameMean  = perFrameMean * scale;
cutStat.perFrameNused = perFrameNused;
cutStat.unit          = unitStr;
cutStat.roi           = roi;
cutStat.nValidFrames  = nnz(validF);
cutStat.nPointsROI    = nPtsROI;
cutStat.filterMode    = FILTER_MODE;
cutStat.vuRatioMax    = VU_RATIO_MAX;
cutStat.pixelSize     = PIXEL_SIZE_MM_PER_PX;
cutStat.dt            = DT_S_PER_FRAME;

%% 5. 명령창 출력 ----------------------------------------------------------
avgUsed = mean(perFrameNused(validF));
fprintf('\n========== 절삭속도 (Cutting Speed) 검증 결과 ==========\n');
fprintf('  보정값: pixelSize = %.5f mm/px , dt = %.6f s/frame (= %.1f fps)\n', ...
        PIXEL_SIZE_MM_PER_PX, DT_S_PER_FRAME, 1/DT_S_PER_FRAME);
fprintf('  ROI [xMin xMax yMin yMax] = [%.1f  %.1f  %.1f  %.1f] (px)\n', roi);
fprintf('  필터: %s', FILTER_MODE);
switch lower(FILTER_MODE)
    case 'ratio', fprintf(' (|V|/|U| < %.2f, |U| >= %.2f px/frame)\n', VU_RATIO_MAX, U_MIN_PX);
    case 'abs',   fprintf(' (|V| < %.2f, |U| >= %.2f px/frame)\n',     V_MAX_ABS,    U_MIN_PX);
    otherwise,    fprintf('\n');
end
fprintf('  ROI 내 PIV 벡터 = %d , 채택된 평균 벡터수 = %.1f / 프레임\n', ...
        nPtsROI, avgUsed);
fprintf('  유효 프레임 = %d / %d , 단위 = %s\n', cutStat.nValidFrames, Nt, unitStr);
fprintf('  ---------------------------------------------------------\n');
fprintf('  최대 속도          : %10.4f %s\n', cutStat.maxSpeed,   unitStr);
fprintf('  최소 속도          : %10.4f %s\n', cutStat.minSpeed,   unitStr);
fprintf('  전체 평균 속도     : %10.4f %s\n', cutStat.meanSpeed,  unitStr);
fprintf('  처음 3프레임 평균  : %10.4f %s\n', cutStat.meanFirst3, unitStr);
fprintf('  마지막 3프레임 평균: %10.4f %s\n', cutStat.meanLast3,  unitStr);
fprintf('=========================================================\n\n');

%% 6. (선택) 시각화: ROI + 채택된 점 ----------------------------------------
if opt.show
    figure('Name','Cutting Speed: ROI & accepted points','Color','w');
    imagesc(X(1,:), Y(:,1), abs(U(:,:,1)));
    axis image; set(gca,'YDir','reverse'); colormap(parula); colorbar; hold on;
    % ROI 박스
    rectangle('Position',[xMin yMin xMax-xMin yMax-yMin], ...
              'EdgeColor','r','LineWidth',2);
    % 한 번이라도 채택된 점들 (녹색 점)
    plot(X(acceptedMaskAccum), Y(acceptedMaskAccum), '.', ...
         'Color',[0 0.8 0], 'MarkerSize', 6);
    title(sprintf('ROI (red) & accepted horizontal-flow points (green)  [filter: %s]', FILTER_MODE));
    xlabel('x [px]'); ylabel('y [px]');
    legend({'ROI box','Accepted points'}, 'Location','best');
end

%% 7. 호출자가 출력 받지 않으면 결과를 base 워크스페이스에 저장 ------------
if nargout == 0
    assignin('base', 'cutStat', cutStat);
    fprintf('[MAENG_CuttingSpeedAnalyze] 결과 구조체를 base 워크스페이스 ''cutStat''에 저장했습니다.\n\n');
    clear cutStat;
end

end
