function spotData = pivSpotVelocityTime(pivData, spotCoords)
% pivSpotVelocityTime - 표면(spot) 속도의 "시간변화" 추적 및 플롯
% -------------------------------------------------------------------------
%   원본 pivVelocityDistrib.m 에서 파생.
%
%   [바뀐 점]
%   (1) 3D mesh(라인을 Y축으로 엮어 격자로 연결하던 시각화) → 완전히 제거.
%   (2) "직선을 따른 공간 속도분포" 대신,
%       사용자가 지정한 N개의 spot 지점(표면/라인 우측 끝 위치 등)에서
%       전체 프레임(시간축)에 걸친 속도를 추출하여 시간변화 양상을 플롯.
%
%   [실행 방법]
%   - 에디터에서 F5(▶)만 눌러도 base workspace의 pivData를 자동 로드.
%   - 추적할 spot 개수는 아래 [사용자 설정 영역]의 numSpots 로 자유 지정.
%   - 함수 호출 시 spotCoords(N×2, [x y] 픽셀좌표)를 직접 넘기면 클릭 생략.
%
%   [출력]
%   spotData 구조체:
%     .t          : 시간축 벡터 (단위는 timeUnit 설정 따름)
%     .tUnit      : 시간축 단위 문자열
%     .coords     : spot 좌표 (N×2, 픽셀)
%     .Vmag       : 각 spot의 속도크기 시계열 (N×Nt) [mm/s]
%     .U, .V      : 각 spot의 U/V 성분 시계열 (N×Nt) [mm/s]
%     .Vsel       : 실제 플롯에 사용된 성분 (velComp 설정에 따름)
% =========================================================================

    % =====================================================================
    % [사용자 설정 영역]  ← 여기만 고치면 됨
    % =====================================================================
    FPS         = 40000;   % 카메라 촬영 속도 [Hz]  (시간 간격 = 1/FPS)
    px2um       = 3.12;    % 1픽셀당 실제 길이 [um/px]
    numSpots    = 4;       % ★ 추적할 spot 개수 (4개보다 많아도 됨)
    velComp     = 'mag';   % 플롯할 속도성분: 'mag'(크기) / 'u'(수평) / 'v'(수직)
    timeUnit    = 'ms';    % 시간축 단위: 'ms' / 'us' / 'frame'
    smoothWinT  = 3;       % 시간축 속도 스무딩 윈도우 (1 = 스무딩 안함)
    fillTimeNaN = true;    % 시간축 중간 NaN(마스크/장외)을 선형보간으로 채움
    smoothSigma = 1.5;     % 배경 표시용 Gaussian 스무딩 sigma [px]
    snapToValid = false;   % true면 클릭점을 가장 가까운 유효(비마스크) 격자로 스냅
    % =====================================================================

    % =====================================================================
    % [1] pivData 자동 로드
    % =====================================================================
    if nargin < 1 || isempty(pivData)
        try
            pivData = evalin('base', 'pivData');
            fprintf('>> [자동] workspace에서 pivData 로드 완료\n');
        catch
            error('workspace에 pivData가 없습니다. PIV 분석 먼저 실행하세요.');
        end
    end
    if nargin < 2, spotCoords = []; end

    % =====================================================================
    % [2] 그리드 / 시간 정보 추출
    % =====================================================================
    X_grid = pivData.X;
    Y_grid = pivData.Y;
    U_all  = pivData.U;
    V_all  = pivData.V;

    % 단일 프레임(2D) 입력도 안전하게 처리
    if ndims(U_all) == 2
        U_all = reshape(U_all, size(U_all,1), size(U_all,2), 1);
        V_all = reshape(V_all, size(V_all,1), size(V_all,2), 1);
    end
    Nt = size(U_all, 3);
    if Nt < 2
        warning('프레임이 1개뿐입니다. 시간변화 플롯이 단일 점으로 표시될 수 있습니다.');
    end
    fprintf('>> 총 %d 프레임 (시간축)\n', Nt);

    % 속도 변환 계수: (px/frame) -> [mm/s]
    vScale = px2um * FPS / 1000;

    % 시간축 벡터 생성
    dt_s = 1 / FPS;
    switch lower(timeUnit)
        case 'us',    t_axis = (0:Nt-1) * dt_s * 1e6;  t_label = 'Time (\mus)';
        case 'frame', t_axis = (0:Nt-1);               t_label = 'Frame #';
        otherwise,    t_axis = (0:Nt-1) * dt_s * 1e3;  t_label = 'Time (ms)';
    end

    x_vec = X_grid(1, :);
    y_vec = Y_grid(:, 1);

    % =====================================================================
    % [3] spot 선택용 배경 속도장(시간평균) 생성
    %     - 마스크 판별 + 내부 NaN 채움 + 표시용 스무딩
    % =====================================================================
    U_ref = mean(U_all, 3, 'omitnan');
    V_ref = mean(V_all, 3, 'omitnan');

    % 마스크(테두리에 닿는 NaN 덩어리)와 내부 NaN(결측) 구분
    nan_all_pre   = isnan(U_ref);
    interior_pre  = imclearborder(nan_all_pre);
    true_mask_pre = nan_all_pre & ~interior_pre;     % 실제 마스크 영역

    % 속도 크기(표시용) [mm/s]
    V_mag_raw  = sqrt(U_ref.^2 + V_ref.^2) * vScale;
    valid_vals = V_mag_raw(~isnan(V_mag_raw) & ~isinf(V_mag_raw));
    if ~isempty(valid_vals)
        vMin = 0;  vMax = prctile(valid_vals, 98);
    else
        vMin = 0;  vMax = 1;
    end

    % 내부 NaN 채움
    V_display    = V_mag_raw;
    interior_nan = isnan(V_mag_raw) & ~true_mask_pre;
    if any(interior_nan(:))
        try
            Vf = inpaintn(V_mag_raw);
            V_display(interior_nan) = Vf(interior_nan);
        catch
            % inpaintn 실패 시 표시용이므로 그대로 둠
        end
    end

    % 마스크 가중 Gaussian 스무딩 (마스크가 번지지 않도록)
    W            = double(~true_mask_pre);
    V_tmp        = V_display;  V_tmp(true_mask_pre) = 0;
    V_display    = imgaussfilt(V_tmp, smoothSigma) ./ ...
                   max(imgaussfilt(W, smoothSigma), 1e-6);
    V_display(true_mask_pre) = NaN;

    % 커스텀 컬러맵 (원본과 동일)
    n = 256;
    cmap_pts = [ 0.00, 0.00, 0.00, 0.50;
                 0.25, 0.00, 0.30, 1.00;
                 0.50, 0.00, 0.85, 0.95;
                 0.75, 1.00, 0.90, 0.00;
                 1.00, 0.80, 0.10, 0.00 ];
    tv   = linspace(0,1,n)';
    cmap = [ interp1(cmap_pts(:,1), cmap_pts(:,2), tv, 'pchip'), ...
             interp1(cmap_pts(:,1), cmap_pts(:,3), tv, 'pchip'), ...
             interp1(cmap_pts(:,1), cmap_pts(:,4), tv, 'pchip') ];
    cmap = max(0, min(1, cmap));

    % =====================================================================
    % [4] spot 지점 지정 (클릭 또는 인자로 전달)
    % =====================================================================
    if isempty(spotCoords)
        colors = lines(max(numSpots,1));

        figS = figure('Name','Spot 지정 (시간평균 속도장)', ...
                      'NumberTitle','off','Color','w');
        imagesc(x_vec, y_vec, V_display, [vMin, vMax]);
        set(gca,'YDir','reverse'); axis image;
        colormap(gca, cmap);
        cb = colorbar; cb.Label.String = '|V| (time-avg, mm/s)';
        xlabel('X [px]'); ylabel('Y [px]');
        title(sprintf('추적할 spot %d개를 클릭하세요 (표면/라인 우측 끝 지점)', numSpots));
        hold on;

        [xs, ys] = ginput(numSpots);
        if isempty(xs)
            disp('취소됨'); try close(figS); catch; end
            spotData = struct(); return;
        end
        spotCoords = [xs(:), ys(:)];

        % (옵션) 가장 가까운 유효 격자점으로 스냅
        if snapToValid
            validMask = ~true_mask_pre & ~isnan(U_ref);
            xv = X_grid(validMask); yv = Y_grid(validMask);
            for i = 1:size(spotCoords,1)
                d2 = (xv-spotCoords(i,1)).^2 + (yv-spotCoords(i,2)).^2;
                [~, im] = min(d2);
                spotCoords(i,:) = [xv(im), yv(im)];
            end
        end

        for i = 1:size(spotCoords,1)
            plot(spotCoords(i,1), spotCoords(i,2), 'o', ...
                 'MarkerFaceColor',colors(i,:), 'MarkerEdgeColor','k', 'MarkerSize',9);
            text(spotCoords(i,1)+8, spotCoords(i,2), sprintf('S%d',i), ...
                 'Color','k','BackgroundColor','w','EdgeColor','k', ...
                 'Margin',1,'FontWeight','bold');
        end
        title(sprintf('spot 지정 완료 — %d개', size(spotCoords,1)));
        hold off;
    end

    numSpots = size(spotCoords,1);
    colors   = lines(numSpots);

    % =====================================================================
    % [5] 각 spot의 시간축 속도 추출
    %     - 매 프레임마다 (x,y) 위치에서 U,V 선형보간 → 속도 계산
    % =====================================================================
    Vmag = nan(numSpots, Nt);   % 속도 크기 [mm/s]
    Ucmp = nan(numSpots, Nt);   % U 성분  [mm/s]
    Vcmp = nan(numSpots, Nt);   % V 성분  [mm/s]

    for kt = 1:Nt
        Uk = U_all(:,:,kt);
        Vk = V_all(:,:,kt);
        for i = 1:numSpots
            xs = spotCoords(i,1);  ys = spotCoords(i,2);
            u = interp2(X_grid, Y_grid, Uk, xs, ys, 'linear');
            v = interp2(X_grid, Y_grid, Vk, xs, ys, 'linear');
            Ucmp(i,kt) = u * vScale;
            Vcmp(i,kt) = v * vScale;
            Vmag(i,kt) = sqrt(u^2 + v^2) * vScale;
        end
    end

    % 플롯에 쓸 성분 선택
    switch lower(velComp)
        case 'u',  Vsel = Ucmp;  vc_label = 'Velocity U (mm/s)';
        case 'v',  Vsel = Vcmp;  vc_label = 'Velocity V (mm/s)';
        otherwise, Vsel = Vmag;  vc_label = 'Velocity Magnitude (mm/s)';
    end

    % 시간축 NaN 보간 + 시계열 스무딩
    for i = 1:numSpots
        row = Vsel(i,:);
        if fillTimeNaN
            ok = ~isnan(row);
            if nnz(ok) >= 2
                row = interp1(t_axis(ok), row(ok), t_axis, 'linear', 'extrap');
            end
        end
        if smoothWinT > 1
            row = movmean(row, smoothWinT, 'omitnan');
        end
        Vsel(i,:) = row;
    end

    % =====================================================================
    % [6] Figure 1 — 전체 spot 속도-시간 오버레이
    % =====================================================================
    figure('Name','Spot Velocity vs Time (overlay)', ...
           'Color','w','NumberTitle','off','Position',[150,150,900,500]);
    hold on;
    leg = cell(1, numSpots);
    for i = 1:numSpots
        plot(t_axis, Vsel(i,:), '-', 'Color',colors(i,:), 'LineWidth',1.8);
        leg{i} = sprintf('Spot %d', i);
    end
    grid on; box on;
    xlabel(t_label); ylabel(vc_label);
    title('Surface spot velocity over time', 'FontWeight','bold','FontSize',12);
    legend(leg, 'Location','best');
    hold off;

    % =====================================================================
    % [7] Figure 2 — spot별 개별 subplot
    % =====================================================================
    nCol = min(numSpots, 4);
    nRow = ceil(numSpots / nCol);
    figure('Name','Spot Velocity vs Time (each)', ...
           'Color','w','NumberTitle','off', ...
           'Position',[200,120,320*nCol,260*nRow]);
    for i = 1:numSpots
        subplot(nRow, nCol, i);
        plot(t_axis, Vsel(i,:), '-', 'Color',colors(i,:), 'LineWidth',1.5);
        grid on;
        xlabel(t_label); ylabel(vc_label);
        title(sprintf('Spot %d  (x=%.0f, y=%.0f px)', ...
                      i, spotCoords(i,1), spotCoords(i,2)));
    end

    % =====================================================================
    % [8] 출력 구조체 정리
    % =====================================================================
    spotData.t         = t_axis;
    spotData.tUnit     = timeUnit;
    spotData.coords    = spotCoords;
    spotData.Vmag      = Vmag;
    spotData.U         = Ucmp;
    spotData.V         = Vcmp;
    spotData.Vsel      = Vsel;
    spotData.component = velComp;
    spotData.FPS       = FPS;
    spotData.px2um     = px2um;

    % 통계 요약 출력
    fprintf('\n========== Spot 속도 시간추적 결과 ==========\n');
    for i = 1:numSpots
        fprintf('  Spot %d (x=%.0f, y=%.0f) : mean=%.2f  max=%.2f  min=%.2f [mm/s]\n', ...
            i, spotCoords(i,1), spotCoords(i,2), ...
            mean(Vsel(i,:),'omitnan'), max(Vsel(i,:),[],'omitnan'), min(Vsel(i,:),[],'omitnan'));
    end
    fprintf('=============================================\n\n');

    % 호출자가 출력 안 받으면 base workspace에 저장
    if nargout == 0
        assignin('base', 'spotData', spotData);
        fprintf('>> 결과 구조체를 base workspace ''spotData''에 저장했습니다.\n');
        clear spotData;
    end

end  % ← 메인 함수 끝
