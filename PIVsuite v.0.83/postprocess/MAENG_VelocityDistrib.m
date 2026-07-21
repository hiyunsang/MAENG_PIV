function [s_cell, vn_cell, grad_cell, xLine_cell, yLine_cell] = MAENG_VelocityDistrib(pivData, lineCoords)
% MAENG_VelocityDistrib - PIV 속도 분포 분석 및 시각화
%  1. F5만 눌러도 workspace에서 pivData 자동 로드
%  2. 커스텀 컬러맵 + Gaussian 스무딩 + 내부 NaN 채움
%  3. 기준선 1개 클릭 → 마스크 경계까지 양방향 자동 연장 + 평행선 동일 처리
%  4. (옵션) 다각형 마스크 — 사용자가 그린 도형 안쪽만 색칠
%  5. (옵션) 라인별 끝점 지정 — 각 라인 위 점 클릭으로 거리(x축) 길이 개별 설정
%  6. 스트레인 레이트 끝 거리(um) 사용자 입력
%  7. Figure 3: 각 라인의 2D 속도 프로파일을 3차원에 독립 배치 (라인 간 연결 mesh 없음       )
%  8. 프레임 선택: 단일 프레임 / 구간(A-B) 평균 / 전체 시간평균 모두 지원
%  9. Figure 2: 라인 간 축(속도/스트레인/거리) 통일 + 논문용 tiledlayout 스타일
% 10. 배경 오버레이 이미지 프레임 선택: 디폴트(자동) + 사용자 지정(BG_FRAME / BG_IMG_PATH)  ← 추가

    % =====================================================================
    % [사용자 설정 영역]
    % =====================================================================
    FPS           = 10000;    % 카메라 촬영 속도 [Hz]
    px2um         = 2.34;    % 1픽셀당 실제 길이 [um/px]
    smoothWin     = 9;       % 속도 프로파일 스무딩 윈도우 크기
    smoothSigma   = 1.5;     % 표시용 Gaussian 스무딩 sigma [픽셀]
    walkStep      = 1;       % 마스크 경계 탐색 보폭 [픽셀]
    USE_POLY_MASK = false;   % 다각형 마스킹 — true(=yes): 다각형 안쪽만 색칠 / false: 전체
    SET_LINE_ENDS = false;   % 라인별 끝점 지정 — true(=yes): 각 라인 끝을 클릭으로 설정 / false: 마스크 끝까지

    % --- 배경(오버레이) 이미지 프레임 설정 ------------------------------
    BG_FRAME    = 100;   % 속도장 위에 겹칠 원본 이미지 프레임 번호
                         %   0 = 자동(디폴트): 속도장 선택 프레임과 동일
                         %       (단일→그 프레임 / 구간→시작 프레임 / 전체평균→1번)
                         %   N = N번 프레임 이미지를 강제로 배경에 사용 (1 ~ Nt)
    BG_IMG_PATH = '';    % (선택) 배경 이미지 파일 경로 직접 지정 — 지정 시 최우선

    % --- Figure 2 논문용 스타일 / 축 통일 설정 ---------------------------
    UNIFY_VEL_AXIS    = true;   % 속도(x) 축 라인 간 통일   ← 요청사항
    UNIFY_STRAIN_AXIS = true;   % 스트레인레이트(x) 축 통일 (일관성)
    UNIFY_DIST_AXIS   = true;   % 거리(y) 축 통일 (열 정렬)
    FONT_NAME = 'Arial';        % 논문용 폰트
    FS_AX     = 10;             % 축 눈금 폰트 크기
    FS_LBL    = 11;             % 축 라벨 폰트 크기
    FS_TTL    = 12;             % 패널 제목 폰트 크기
    LW_LINE   = 1.8;            % 데이터 선 두께
    SAVE_FIG2 = true;           % Figure 2 PNG/PDF 저장
    % =====================================================================

    % =====================================================================
    % [1] pivData 자동 로드
    % =====================================================================
    if nargin < 1
        try
            pivData = evalin('base', 'pivData');
            fprintf('>> [자동] workspace에서 pivData 로드 완료\n');
        catch
            error('workspace에 pivData가 없습니다. PIV 분석 먼저 실행하세요.');
        end
    end
    if nargin < 2, lineCoords = []; end

    % =====================================================================
    % [2] 프레임 선택 — 단일 / 구간 평균 / 전체 평균
    %     입력 예:
    %        0      → 전체 시간평균 (모든 프레임)
    %        7      → 7번 단일 프레임
    %        10-20  → 10~20번 프레임 구간 평균
    %                 (구분자는 -, :, ~, 공백, 쉼표 모두 허용:  10:20 / 10 20 / 10,20)
    % =====================================================================
    X_grid = pivData.X;
    Y_grid = pivData.Y;
    Nt     = size(pivData.U, 3);

    avg_mode = 'single';   % 'single' | 'range' | 'all'
    fr_lo    = 1;          % 구간 시작 프레임
    fr_hi    = 1;          % 구간 끝   프레임

    if Nt > 1
        ans_f = inputdlg( ...
            sprintf(['총 %d 프레임\n' ...
                     '  0      = 전체 시간평균\n' ...
                     '  N      = N번 단일 프레임\n' ...
                     '  A-B    = A~B번 구간 평균'], Nt), ...
            '프레임 선택', 1, {'0'});
        if isempty(ans_f), disp('취소됨'); return; end

        raw  = strtrim(ans_f{1});
        % 구분자(- : ~ , 공백)를 공백으로 통일한 뒤 숫자만 추출
        nums = sscanf(regexprep(raw, '[-:~,]', ' '), '%g');

        if isscalar(nums)
            if nums == 0
                avg_mode = 'all';
            else
                avg_mode = 'single';
                fr_lo = round(nums);   fr_hi = fr_lo;
            end
        elseif numel(nums) >= 2
            avg_mode = 'range';
            fr_lo = round(min(nums(1), nums(2)));
            fr_hi = round(max(nums(1), nums(2)));
        else
            avg_mode = 'all';          % 파싱 실패 → 안전하게 전체 평균
        end
    end

    % --- 프레임 인덱스 경계 보정 ---
    if ~strcmp(avg_mode, 'all')
        fr_lo = max(1, min(Nt, fr_lo));
        fr_hi = max(1, min(Nt, fr_hi));
        if fr_hi < fr_lo, [fr_lo, fr_hi] = deal(fr_hi, fr_lo); end
    end

    % --- 기준 속도장(U_ref, V_ref) 구성 ---
    switch avg_mode
        case 'all'
            U_ref = mean(pivData.U, 3, 'omitnan');
            V_ref = mean(pivData.V, 3, 'omitnan');
            fprintf('>> [프레임] 전체 시간평균 (1 ~ %d)\n', Nt);
        case 'single'
            U_ref = pivData.U(:,:,fr_lo);
            V_ref = pivData.V(:,:,fr_lo);
            fprintf('>> [프레임] 단일 프레임 #%d\n', fr_lo);
        case 'range'
            U_ref = mean(pivData.U(:,:,fr_lo:fr_hi), 3, 'omitnan');
            V_ref = mean(pivData.V(:,:,fr_lo:fr_hi), 3, 'omitnan');
            fprintf('>> [프레임] 구간 평균 #%d ~ #%d  (%d 프레임)\n', ...
                    fr_lo, fr_hi, fr_hi - fr_lo + 1);
    end

    % 배경 이미지용 대표 프레임 (구간이면 시작 프레임, 전체면 1번) — [3]에서 사용
    if strcmp(avg_mode, 'all'), sel_frame = 1; else, sel_frame = fr_lo; end

    nan_all_pre   = isnan(U_ref);
    interior_pre  = imclearborder(nan_all_pre);
    true_mask_pre = nan_all_pre & ~interior_pre;
    mask_double   = double(true_mask_pre);

    xMin = min(X_grid(:)); xMax = max(X_grid(:));
    yMin = min(Y_grid(:)); yMax = max(Y_grid(:));

    % =====================================================================
    % [3] 배경 원본 이미지 로드 (오버레이 프레임 선택 가능)
    %     속도장 프레임과 배경 이미지 프레임을 분리:
    %       · BG_IMG_PATH 지정 → 그 파일을 최우선 사용 (우선순위 1)
    %       · BG_FRAME = N (1~Nt) → N번 프레임 이미지를 강제 사용
    %       · BG_FRAME = 0 → 자동(디폴트): 속도장 선택 프레임(sel_frame)
    %     예: 전체평균 속도장 위에 발달된 BUE 프레임을 깔고 싶을 때 BG_FRAME 지정
    % =====================================================================
    bg_img = [];

    % --- (우선순위 1) 경로 직접 지정 시 최우선 ---
    if ~isempty(BG_IMG_PATH) && exist(BG_IMG_PATH, 'file')
        bg_img = imread(BG_IMG_PATH);
        fprintf('>> [배경] 직접 지정 경로 사용: %s\n', BG_IMG_PATH);
    else
        % --- 오버레이에 사용할 프레임 번호 결정 ---
        if BG_FRAME >= 1 && BG_FRAME <= Nt
            bg_frame = round(BG_FRAME);
            fprintf('>> [배경] 사용자 지정 프레임 #%d\n', bg_frame);
        else
            bg_frame = max(1, min(Nt, sel_frame));
            if BG_FRAME ~= 0
                fprintf('>> [배경] BG_FRAME=%g 범위 밖(1~%d) → 자동 프레임 #%d 사용\n', ...
                        BG_FRAME, Nt, bg_frame);
            else
                fprintf('>> [배경] 자동(디폴트) 프레임 #%d\n', bg_frame);
            end
        end

        % --- (우선순위 2) pivData 파일명 목록에서 bg_frame 로드 ---
        fn_target = '';
        if isfield(pivData,'imFilename1') && ~isempty(pivData.imFilename1)
            fn_target = pivData.imFilename1;
        elseif isfield(pivData,'imFilename2') && ~isempty(pivData.imFilename2)
            fn_target = pivData.imFilename2;
        end

        if iscell(fn_target)
            idx = max(1, min(bg_frame, length(fn_target)));
            fn_target = fn_target{idx};
        elseif isstring(fn_target) && length(fn_target) > 1
            fn_target = char(fn_target(max(1, min(bg_frame, length(fn_target)))));
        else
            fn_target = char(fn_target);
        end

        if ~isempty(fn_target) && exist(fn_target, 'file')
            bg_img = imread(fn_target);
            fprintf('>> [배경] 이미지 파일: %s\n', fn_target);
        else
            % --- (우선순위 3) 마지막 폴백: 수동 선택 ---
            disp('>> [알림] 원본 이미지를 찾을 수 없습니다.');
            [file, path] = uigetfile({'*.png;*.jpg;*.tif;*.bmp','Image Files'}, ...
                '배경 이미지 선택 (취소 시 배경 없음)');
            if ischar(file)
                bg_img = imread(fullfile(path, file));
            end
        end
    end

    % =====================================================================
    % [4] 선 생성 — 기준선 1개 클릭 → 마스크까지 자동 연장 + 평행선
    % =====================================================================
    numLines = 1;
    colors   = pubColors(1);

    if isempty(lineCoords)

        dlg = inputdlg( ...
            {'생성할 선의 총 개수 :','Y 방향 간격 (픽셀, 위 방향) :'}, ...
            '선 설정', 1, {'4','30'});
        if isempty(dlg), disp('취소됨'); return; end
        numLines_req = str2double(dlg{1});
        yInterval    = str2double(dlg{2});

        colors = pubColors(numLines_req);

        fig_sel = figure('Name','기준 선 클릭 (방향 지정)', 'NumberTitle','off');
        quiver(X_grid, Y_grid, U_ref, V_ref, 'Color',[0.7 0.7 0.7]);
        axis image; set(gca,'YDir','reverse');
        xlabel('X [px]'); ylabel('Y [px]');
        title('선의 기울기를 지정할 2점을 클릭 (길이는 마스크까지 자동 연장)');
        hold on;

        [x_sel, y_sel] = ginput(2);

        dx_raw = x_sel(2) - x_sel(1);
        dy_raw = y_sel(2) - y_sel(1);
        L_raw  = sqrt(dx_raw^2 + dy_raw^2);
        tx = dx_raw / L_raw;
        ty = dy_raw / L_raw;

        xmid_base = (x_sel(1) + x_sel(2)) / 2;
        ymid_base = (y_sel(1) + y_sel(2)) / 2;

        [xa1, ya1, xb1, yb1] = extendLine( ...
            xmid_base, ymid_base, tx, ty, ...
            X_grid, Y_grid, mask_double, xMin, xMax, yMin, yMax, walkStep);

        lineCoords    = cell(1, numLines_req);
        lineCoords{1} = [xa1, ya1; xb1, yb1];
        valid_count   = 1;

        plot([xa1 xb1], [ya1 yb1], '-', 'Color',colors(1,:), 'LineWidth',2.5);
        plot(xa1, ya1, 'o', 'Color',colors(1,:), 'MarkerFaceColor',colors(1,:));
        text(xa1, ya1-15, 'L1', 'Color',colors(1,:), 'FontWeight','bold');

        for k = 1:numLines_req-1
            ymid_k = ymid_base - yInterval * k;
            xmid_k = xmid_base;

            m_ctr = interp2(X_grid, Y_grid, mask_double, xmid_k, ymid_k, 'nearest', 1);
            if m_ctr > 0.5
                fprintf('>> Line %d: 중심점이 마스크 → 제외\n', k+1);
                continue;
            end

            [xa_k, ya_k, xb_k, yb_k] = extendLine( ...
                xmid_k, ymid_k, tx, ty, ...
                X_grid, Y_grid, mask_double, xMin, xMax, yMin, yMax, walkStep);

            seg_len = sqrt((xb_k-xa_k)^2 + (yb_k-ya_k)^2);
            if seg_len < 5
                fprintf('>> Line %d: 유효 길이 너무 짧음 → 제외\n', k+1);
                continue;
            end

            valid_count = valid_count + 1;
            lineCoords{valid_count} = [xa_k, ya_k; xb_k, yb_k];

            ci = min(valid_count, size(colors,1));
            plot([xa_k xb_k], [ya_k yb_k], '-', 'Color',colors(ci,:), 'LineWidth',2.5);
            plot(xa_k, ya_k, 'o', 'Color',colors(ci,:), 'MarkerFaceColor',colors(ci,:));
            text(xa_k, ya_k-15, sprintf('L%d',valid_count), ...
                 'Color',colors(ci,:), 'FontWeight','bold');
        end

        lineCoords = lineCoords(1:valid_count);
        numLines   = valid_count;
        colors     = pubColors(numLines);

        title(sprintf('선 생성 완료 — %d개', numLines));
        hold off;
        try close(fig_sel); catch; end

    else
        if ~iscell(lineCoords), lineCoords = {lineCoords}; end
        numLines = length(lineCoords);
        colors   = pubColors(numLines);
    end

    % =====================================================================
    % [5] 속도 크기 계산 + 표시용 처리
    % =====================================================================
    V_mag_raw = sqrt(U_ref.^2 + V_ref.^2) * (px2um * FPS) / 1000;  % [mm/s]

    valid_vals = V_mag_raw(~isnan(V_mag_raw) & ~isinf(V_mag_raw));
    if ~isempty(valid_vals)
        fprintf('>> [속도 범위] Min=%.2f  Max=%.2f  Mean=%.2f [mm/s]\n', ...
            min(valid_vals), max(valid_vals), mean(valid_vals));
        vMin = 0;
        vMax = prctile(valid_vals, 98);
    else
        vMin = 0; vMax = 1;
    end

    nan_all      = isnan(V_mag_raw);
    interior_nan = nan_all & ~true_mask_pre;
    V_display    = V_mag_raw;
    if any(interior_nan(:))
        try
            V_filled = inpaintn(V_mag_raw);
            V_display(interior_nan) = V_filled(interior_nan);
        catch
            [rr, cc] = find(interior_nan);
            for ki = 1:length(rr)
                r = rr(ki); c = cc(ki);
                patch = V_mag_raw(max(1,r-2):min(end,r+2), max(1,c-2):min(end,c+2));
                V_display(r,c) = mean(patch(~isnan(patch)), 'omitnan');
            end
        end
    end

    W            = double(~true_mask_pre);
    V_tmp        = V_display; V_tmp(true_mask_pre) = 0;
    V_smooth_num = imgaussfilt(V_tmp, smoothSigma);
    V_smooth_den = imgaussfilt(W,     smoothSigma);
    V_display    = V_smooth_num ./ max(V_smooth_den, 1e-6);
    V_display(true_mask_pre) = NaN;

    % =====================================================================
    % [5.3] 표시 공통 준비 — 좌표축 벡터 + 커스텀 컬러맵 (이후 단계 공용)
    % =====================================================================
    x_vec = X_grid(1, :);
    y_vec = Y_grid(:, 1);

    n = 256;
    cmap_pts = [ 0.00, 0.00, 0.00, 0.50;
                 0.25, 0.00, 0.30, 1.00;
                 0.50, 0.00, 0.85, 0.95;
                 0.75, 1.00, 0.90, 0.00;
                 1.00, 0.80, 0.10, 0.00 ];
    t_vec = linspace(0,1,n)';
    cmap  = [ interp1(cmap_pts(:,1), cmap_pts(:,2), t_vec, 'pchip'), ...
              interp1(cmap_pts(:,1), cmap_pts(:,3), t_vec, 'pchip'), ...
              interp1(cmap_pts(:,1), cmap_pts(:,4), t_vec, 'pchip') ];
    cmap  = max(0, min(1, cmap));

    % =====================================================================
    % [5.5] 다각형 마스크 — USE_POLY_MASK = true 일 때만
    %       사용자가 그린 다각형 안쪽만 남기고 바깥은 NaN(투명) 처리
    % =====================================================================
    if USE_POLY_MASK
        figP = figure('Name','다각형 마스크 영역 지정','NumberTitle','off','Color','w');
        axP  = axes('Parent', figP);

        if ~isempty(bg_img)
            bgP = bg_img; if size(bgP,3)==1, bgP = repmat(bgP,1,1,3); end
            image(axP, [0, size(bgP,2)-1], [0, size(bgP,1)-1], bgP);
            hold(axP,'on');
        else
            hold(axP,'on');
        end

        hpv = imagesc(axP, x_vec, y_vec, V_display, [vMin, vMax]);
        colormap(axP, cmap);
        set(hpv, 'AlphaData', 0.45*double(~isnan(V_display)));

        axis(axP,'image'); set(axP,'YDir','reverse');
        xlabel(axP,'X [px]'); ylabel(axP,'Y [px]');
        title(axP, '색칠할 영역의 다각형을 그리세요  (꼭짓점 클릭 → 더블클릭/Enter 로 완료)');

        polyX = []; polyY = [];
        try
            hpoly = drawpolygon(axP, 'Color','r', 'LineWidth',2, 'FaceAlpha',0.10);
            if ~isempty(hpoly.Position)
                polyX = hpoly.Position(:,1);
                polyY = hpoly.Position(:,2);
            end
        catch
            [polyX, polyY] = ginput;   % 구버전 폴백 (Enter 로 종료)
        end

        try close(figP); catch; end

        if numel(polyX) >= 3
            inPoly = inpolygon(X_grid, Y_grid, polyX, polyY);
            V_display(~inPoly) = NaN;
            fprintf('>> [다각형 마스크] 꼭짓점 %d개 — 안쪽 영역만 색칠\n', numel(polyX));
        else
            fprintf('>> [다각형 마스크] 꼭짓점 3개 미만 → 미적용 (전체 표시)\n');
        end
    end

    % =====================================================================
    % [5.7] 라인별 끝점(거리) 지정 — SET_LINE_ENDS = true 일 때만
    %       각 라인 위 점을 클릭 → 라인 위로 정사영해 시작점(s=0)부터의 거리로 환산
    %       → 그 거리까지로 라인을 잘라 속도 프로파일의 x축(거리) 길이를 개별 설정
    %       좌클릭=끝점 지정 / 우클릭=이 라인 전체 유지 / Enter=남은 라인 전체 유지
    % =====================================================================
    if SET_LINE_ENDS
        figE = figure('Name','라인별 끝점 지정','NumberTitle','off','Color','w');
        axE  = axes('Parent', figE);

        if ~isempty(bg_img)
            bgE = bg_img; if size(bgE,3)==1, bgE = repmat(bgE,1,1,3); end
            image(axE, [0, size(bgE,2)-1], [0, size(bgE,1)-1], bgE);
            hold(axE,'on');
        else
            hold(axE,'on');
        end

        hpe = imagesc(axE, x_vec, y_vec, V_display, [vMin, vMax]);
        colormap(axE, cmap);
        set(hpe, 'AlphaData', 0.45*double(~isnan(V_display)));
        axis(axE,'image'); set(axE,'YDir','reverse');
        xlabel(axE,'X [px]'); ylabel(axE,'Y [px]');

        % 전체 라인 + 시작점(s=0) 마커 표시
        hLines = gobjects(1, numLines);
        for i = 1:numLines
            hLines(i) = plot(axE, lineCoords{i}(:,1), lineCoords{i}(:,2), ...
                             '-', 'Color',colors(i,:), 'LineWidth',2);
            plot(axE, lineCoords{i}(1,1), lineCoords{i}(1,2), 'o', ...
                 'Color',colors(i,:), 'MarkerFaceColor',colors(i,:), 'MarkerSize',7);
            text(axE, lineCoords{i}(1,1), lineCoords{i}(1,2)-15, sprintf('L%d',i), ...
                 'Color','k','BackgroundColor','w','FontWeight','bold');
        end

        for i = 1:numLines
            title(axE, sprintf(['L%d 끝점 클릭   ', ...
                  '(좌클릭=끝점 / 우클릭=이 라인 전체 / Enter=남은 라인 전체)'], i));
            set(hLines(i), 'LineWidth', 5, 'Color', [1 0.85 0]);   % 현재 라인 강조

            [px, py, btn] = ginput(1);
            set(hLines(i), 'LineWidth', 2, 'Color', colors(i,:));  % 강조 해제

            if isempty(px), break; end          % Enter → 남은 라인 전체 유지
            if btn == 3                          % 우클릭 → 이 라인 전체 유지
                fprintf('>> Line %d: 끝점 미지정 (전체 유지)\n', i);
                continue;
            end

            x1 = lineCoords{i}(1,1); y1 = lineCoords{i}(1,2);
            x2 = lineCoords{i}(2,1); y2 = lineCoords{i}(2,2);
            dx = x2-x1; dy = y2-y1; Lf = hypot(dx,dy);
            if Lf < eps, continue; end
            tx = dx/Lf; ty = dy/Lf;

            % 클릭점을 라인 위로 정사영 → 시작점부터의 거리
            s_end_px = (px - x1)*tx + (py - y1)*ty;
            s_end_px = max(5, min(Lf, s_end_px));   % [5px, 전체길이]로 클램프

            x2n = x1 + s_end_px*tx;  y2n = y1 + s_end_px*ty;
            lineCoords{i} = [x1, y1; x2n, y2n];      % 라인 절단
            set(hLines(i), 'XData', [x1 x2n], 'YData', [y1 y2n]);
            plot(axE, x2n, y2n, 's', 'Color',colors(i,:), ...
                 'MarkerFaceColor','w', 'MarkerSize',8, 'LineWidth',1.5);

            fprintf('>> Line %d 끝점: %.0f px  (%.1f um)\n', ...
                    i, s_end_px, s_end_px*px2um);
        end

        title(axE, '라인 끝점 지정 완료');
        pause(0.3);
        try close(figE); catch; end
    end

    % =====================================================================
    % [6] 오버레이 플롯 — 속도 맵 + 라인
    % =====================================================================
    figure('Name','Velocity Map (Masked = Original Image)', ...
           'Color','w','NumberTitle','off');
    ax = axes;

    if ~isempty(bg_img)
        if size(bg_img,3) == 1, bg_img = repmat(bg_img,1,1,3); end
        image(ax, [0, size(bg_img,2)-1], [0, size(bg_img,1)-1], bg_img);
        hold(ax,'on');
    else
        hold(ax,'on');
    end

    h_vel = imagesc(ax, x_vec, y_vec, V_display, [vMin, vMax]);
    colormap(ax, cmap);
    set(h_vel, 'AlphaData', double(~isnan(V_display)));

    axis(ax,'image'); set(ax,'YDir','reverse');
    clim(ax,[vMin, vMax]);
    cb = colorbar(ax);
    cb.Label.String = 'Velocity Magnitude (mm/s)';
    cb.Label.FontSize = 11;
    title(ax,'Velocity Map (Masked regions: original image)', ...
          'FontWeight','bold','FontSize',12);
    xlabel(ax,'X [px]'); ylabel(ax,'Y [px]');

    for i = 1:numLines
        plot(ax, lineCoords{i}(:,1), lineCoords{i}(:,2), '-', ...
             'Color',colors(i,:), 'LineWidth',2.5);
        plot(ax, lineCoords{i}(1,1), lineCoords{i}(1,2), 'o', ...
             'Color',colors(i,:), 'MarkerFaceColor',colors(i,:), 'MarkerSize',7);
        text(ax, lineCoords{i}(1,1), lineCoords{i}(1,2)-20, sprintf('L%d',i), ...
             'Color','k','BackgroundColor','w','EdgeColor','k','Margin',1,'FontWeight','bold');
    end
    hold(ax,'off');

    % =====================================================================
    % [7] 스트레인 레이트 플롯 끝 거리 — 사용자 입력 (전역 상한)
    % =====================================================================
    dlg_s = inputdlg({'스트레인 레이트 플롯 끝 거리 X (um)  ※ 0 = 전체:'}, ...
                     '플롯 범위 설정', 1, {'500'});
    if isempty(dlg_s)
        s_end_um = 0;
    else
        s_end_um = str2double(dlg_s{1});
    end
    if s_end_um <= 0
        fprintf('>> 스트레인 레이트: (라인별 끝점 기준) 전체 범위\n');
    else
        fprintf('>> 스트레인 레이트: 0 ~ %.0f um (라인별 끝점과 min 적용)\n', s_end_um);
    end

    % =====================================================================
    % [8] 각 선: 속도 보간 + 법선 속도 + 스무딩 + 구배
    % =====================================================================
    s_cell     = cell(1, numLines);
    vn_cell    = cell(1, numLines);
    grad_cell  = cell(1, numLines);
    xLine_cell = cell(1, numLines);
    yLine_cell = cell(1, numLines);

    for i = 1:numLines
        coords = lineCoords{i};
        x1 = coords(1,1); y1 = coords(1,2);
        x2 = coords(2,1); y2 = coords(2,2);

        dx   = x2-x1; dy = y2-y1;
        L    = sqrt(dx^2+dy^2);
        tx_i = dx/L;  ty_i = dy/L;
        nx_i = -ty_i; ny_i = tx_i;

        numPoints = max(200, ceil(L));
        xLine = linspace(x1, x2, numPoints);
        yLine = linspace(y1, y2, numPoints);

        s_px = sqrt((xLine-x1).^2 + (yLine-y1).^2);
        s_um = s_px * px2um;
        s_mm = s_um / 1000;

        U_line = interp2(X_grid, Y_grid, U_ref, xLine, yLine, 'linear');
        V_line = interp2(X_grid, Y_grid, V_ref, xLine, yLine, 'linear');

        vn_px = U_line.*nx_i + V_line.*ny_i;
        vn_mm = vn_px * (px2um * FPS) / 1000;

        valid_idx = ~isnan(vn_mm);
        if any(valid_idx) && ~all(valid_idx)
            vn_mm = interp1(s_um(valid_idx), vn_mm(valid_idx), s_um, 'linear','extrap');
        elseif ~any(valid_idx)
            vn_mm(:) = 0;
        end

        if smoothWin > 1
            try
                vn_mm = movmean(vn_mm, smoothWin);
            catch
                vn_mm = smooth(vn_mm, smoothWin, 'moving')';
            end
        end

        dv_ds = gradient(vn_mm, s_mm);

        s_cell{i}     = s_um;
        vn_cell{i}    = vn_mm;
        grad_cell{i}  = dv_ds;
        xLine_cell{i} = xLine;
        yLine_cell{i} = yLine;
    end

    % =====================================================================
    % [9] Figure 2 — 속도 & 전단 스트레인 레이트 (논문용 정돈 버전)
    %     · 속도/스트레인 x축, 거리 y축을 라인 간 통일 (UNIFY_* 토글)
    %     · tiledlayout 정밀 간격, Arial 폰트, 내부 열 거리눈금 생략, 보기좋은 축 범위
    %     · 상단행 = 속도 프로파일 / 하단행 = 전단 스트레인 레이트
    % =====================================================================

    % --- (9-1) 전역 축 범위 사전 계산 ------------------------------------
    % 거리(y) 전역 최댓값 (속도 행 기준)
    sMaxAll = 0;
    for i = 1:numLines
        sMaxAll = max(sMaxAll, s_cell{i}(end));
    end
    if sMaxAll <= 0, sMaxAll = 1; end

    % 속도(x) 전역 범위
    vLo = inf; vHi = -inf;
    for i = 1:numLines
        vv = vn_cell{i}(isfinite(vn_cell{i}));
        if ~isempty(vv)
            vLo = min(vLo, min(vv));
            vHi = max(vHi, max(vv));
        end
    end
    if ~isfinite(vLo), vLo = 0; vHi = 1; end
    vpad = 0.05*(vHi - vLo + eps);
    if vLo >= 0
        velXlim = [0, niceCeil(vHi + vpad)];          % 양수 전용 → 0 기준, 상한 라운딩
    else
        velXlim = [niceFloor(vLo - vpad), niceCeil(vHi + vpad)];
    end
    if diff(velXlim) < eps, velXlim = velXlim(1) + [-1 1]; end

    % 스트레인(x) 전역 범위 + 라인별 표시 끝 인덱스(capIdx)
    sCapAll = sMaxAll;
    if s_end_um > 0, sCapAll = min(sCapAll, s_end_um); end
    capIdx = zeros(1, numLines);
    gLo = inf; gHi = -inf;
    for i = 1:numLines
        s_cap_i = s_cell{i}(end);
        if s_end_um > 0, s_cap_i = min(s_cap_i, s_end_um); end
        idx = find(s_cell{i} <= s_cap_i, 1, 'last');
        if isempty(idx), idx = numel(s_cell{i}); end
        capIdx(i) = idx;
        gg = grad_cell{i}(1:idx);
        gg = gg(isfinite(gg));
        if ~isempty(gg)
            gLo = min(gLo, min(gg));
            gHi = max(gHi, max(gg));
        end
    end
    if ~isfinite(gLo), gLo = -1; gHi = 1; end
    gpad = 0.05*(gHi - gLo + eps);
    strXlim = [niceFloor(gLo - gpad), niceCeil(gHi + gpad)];
    if diff(strXlim) < eps, strXlim = strXlim(1) + [-1 1]; end

    % --- (9-2) Figure / tiledlayout --------------------------------------
    figW = max(18, 4.4*numLines);                    % [cm] 패널당 폭 확보
    fig2 = figure('Name','2D Velocity & Shear Strain Rate', ...
                  'NumberTitle','off','Color','w', ...
                  'Units','centimeters','Position',[2 2 figW 12]);
    tl2 = tiledlayout(fig2, 2, numLines, ...
                      'TileSpacing','compact','Padding','compact');

    grayRef = [0.80 0.80 0.80];                      % 0 기준선 색 (옅게)

    % --- (9-3) 상단 행: 속도 프로파일 -----------------------------------
    for i = 1:numLines
        ax = nexttile(tl2, i);

        if UNIFY_VEL_AXIS,  xl = velXlim;  else, xl = [min(vn_cell{i})-eps, max(vn_cell{i})+eps]; end
        if UNIFY_DIST_AXIS, yl = [0 sMaxAll]; else, yl = [0 s_cell{i}(end)]; end

        hold(ax,'on');
        if xl(1) < 0 && xl(2) > 0                    % 0 기준선: x범위 내부일 때만
            plot(ax, [0 0], yl, '-', 'Color',grayRef, 'LineWidth',0.8);
        end
        plot(ax, vn_cell{i}, s_cell{i}, '-', ...
             'Color',colors(i,:), 'LineWidth',LW_LINE);
        hold(ax,'off');
        xlim(ax, xl);  ylim(ax, yl);

        title(ax, sprintf('Line %d', i), ...
              'FontName',FONT_NAME,'FontSize',FS_TTL,'FontWeight','bold');
        xlabel(ax, 'Chip velocity (mm s^{-1})', ...
               'FontName',FONT_NAME,'FontSize',FS_LBL);
        if i == 1
            ylabel(ax, 'Distance from tool tip (\mum)', ...
                   'FontName',FONT_NAME,'FontSize',FS_LBL);
        end
        stylizeAxis(ax, FONT_NAME, FS_AX);
        if i > 1 && UNIFY_DIST_AXIS, set(ax, 'YTickLabel', []); end   % 내부 열 y숫자 생략
    end

    % --- (9-4) 하단 행: 전단 스트레인 레이트 -----------------------------
    for i = 1:numLines
        idx    = capIdx(i);
        s_plot = s_cell{i}(1:idx);
        g_plot = grad_cell{i}(1:idx);

        ax = nexttile(tl2, numLines + i);

        if UNIFY_STRAIN_AXIS, xl = strXlim;  else, xl = [min(g_plot)-eps, max(g_plot)+eps]; end
        if UNIFY_DIST_AXIS,   yl = [0 sCapAll]; else, yl = [0 s_plot(end)]; end

        hold(ax,'on');
        if xl(1) < 0 && xl(2) > 0                    % 0 기준선: x범위 내부일 때만
            plot(ax, [0 0], yl, '-', 'Color',grayRef, 'LineWidth',0.8);
        end
        plot(ax, g_plot, s_plot, '-', ...
             'Color',colors(i,:), 'LineWidth',LW_LINE);
        hold(ax,'off');
        xlim(ax, xl);  ylim(ax, yl);

        xlabel(ax, 'Shear strain rate (s^{-1})', ...
               'FontName',FONT_NAME,'FontSize',FS_LBL);
        if i == 1
            ylabel(ax, 'Distance from tool tip (\mum)', ...
                   'FontName',FONT_NAME,'FontSize',FS_LBL);
        end
        stylizeAxis(ax, FONT_NAME, FS_AX);
        if i > 1 && UNIFY_DIST_AXIS, set(ax, 'YTickLabel', []); end   % 내부 열 y숫자 생략
    end

    % --- (9-5) 저장 (PNG 600 dpi + 벡터 PDF) -----------------------------
    if SAVE_FIG2
        try
            exportgraphics(fig2, 'velocity_strainrate_profiles.png', 'Resolution', 600);
            exportgraphics(fig2, 'velocity_strainrate_profiles.pdf', 'ContentType','vector');
            fprintf('>> [저장] velocity_strainrate_profiles.png / .pdf\n');
        catch ME
            fprintf('>> [저장 실패] %s\n', ME.message);
        end
    end

    % =====================================================================
    % [10] Figure 3 — 각 라인의 2D 속도 프로파일을 3차원에 독립 배치
    %      (라인끼리 연결하는 mesh 제거 → 독립적인 2D 그래프 N개)
    %      X축: 라인을 따른 거리 (um) / Y축: Line index / Z축: 속도 (mm/s)
    % =====================================================================
    figure('Name','3D Velocity Profiles (Distance x Line)', ...
           'Color','w','NumberTitle','off','Position',[600,100,900,650]);
    ax3 = axes;
    hold(ax3, 'on');

    % --- 모든 라인 속도의 최저값 (채움 면의 바닥 기준) ---
    v_floor = inf;
    for i = 1:numLines
        v_i = vn_cell{i};
        v_i = v_i(~isnan(v_i));
        if ~isempty(v_i), v_floor = min(v_floor, min(v_i)); end
    end
    if ~isfinite(v_floor), v_floor = 0; end

    for i = 1:numLines
        s_i = s_cell{i};         % 거리 [um]
        v_i = vn_cell{i};        % 속도 [mm/s]

        ok   = ~isnan(v_i);
        s_ok = s_i(ok);
        v_ok = v_i(ok);
        if numel(s_ok) < 2, continue; end
        y_ok = repmat(i, size(s_ok));

        % (1) 곡선 아래 반투명 면 — 한 평면(Y=i) 안에서만 채움 (라인 간 연결 없음)
        xx = [s_ok, fliplr(s_ok)];
        yy = repmat(i, 1, numel(xx));
        zz = [v_ok, v_floor*ones(1, numel(v_ok))];
        fill3(ax3, xx, yy, zz, colors(i,:), ...
              'FaceAlpha', 0.18, 'EdgeColor', 'none');

        % (2) 속도 프로파일 곡선 (라인 고유 색)
        plot3(ax3, s_ok, y_ok, v_ok, '-', ...
              'Color', colors(i,:), 'LineWidth', 2.2);
    end

    % --- 보기 설정 ---
    xlabel(ax3, 'Distance from tool tip (\mum)', 'FontWeight','bold');
    ylabel(ax3, 'Line',                          'FontWeight','bold');
    zlabel(ax3, 'Velocity (mm/s)',               'FontWeight','bold');
    title(ax3,  'Velocity Profiles across Lines', ...
                'FontWeight','bold','FontSize',12);

    view(ax3, 50, 25);
    set(ax3, 'XDir','reverse');                % 툴팁(0)이 앞쪽에 오도록
    yticks(ax3, 1:numLines);
    yticklabels(ax3, arrayfun(@(x) sprintf('Line %d',x), ...
                              1:numLines, 'UniformOutput', false));
    ylim(ax3, [0.5, numLines+0.5]);
    grid(ax3, 'on');
    set(ax3, 'BoxStyle','full', 'Box','on', ...
             'GridAlpha',0.2, 'LineWidth',1, 'Color','w');
    hold(ax3, 'off');

end  % ← 메인 함수 끝

% =========================================================================
% 로컬 서브함수: 중심점에서 마스크 경계까지 양방향 연장
% =========================================================================
function [xa, ya, xb, yb] = extendLine(xm, ym, tx, ty, ...
    X_grid, Y_grid, mask_double, xMin, xMax, yMin, yMax, walkStep)
    xb = xm; yb = ym;
    for s = 1:10000
        xt = xm + s*walkStep*tx;
        yt = ym + s*walkStep*ty;
        if xt<xMin || xt>xMax || yt<yMin || yt>yMax, break; end
        if interp2(X_grid, Y_grid, mask_double, xt, yt, 'nearest', 1) > 0.5, break; end
        xb = xt; yb = yt;
    end
    xa = xm; ya = ym;
    for s = 1:10000
        xt = xm - s*walkStep*tx;
        yt = ym - s*walkStep*ty;
        if xt<xMin || xt>xMax || yt<yMin || yt>yMax, break; end
        if interp2(X_grid, Y_grid, mask_double, xt, yt, 'nearest', 1) > 0.5, break; end
        xa = xt; ya = yt;
    end
end

% =========================================================================
% 로컬 서브함수: 논문용 색상 팔레트 (저대비 노랑 → 녹색 대체)
% =========================================================================
function C = pubColors(n)
    base = [0.0000 0.4470 0.7410;   % blue
            0.8500 0.3250 0.0980;   % orange-red
            0.4660 0.6740 0.1880;   % green (흰 배경 대비 ↑)
            0.4940 0.1840 0.5560;   % purple
            0.3010 0.7450 0.9330;   % light blue
            0.6350 0.0780 0.1840;   % dark red
            0.2500 0.2500 0.2500];  % gray
    if n <= size(base,1)
        C = base(1:n,:);
    else
        C = [base; lines(n - size(base,1))];
    end
end

% =========================================================================
% 로컬 서브함수: 논문용 축 스타일 일괄 적용
% =========================================================================
function stylizeAxis(ax, fontName, fsAx)
    set(ax, 'FontName',fontName, 'FontSize',fsAx, ...
            'LineWidth',0.9, 'TickDir','out', 'TickLength',[0.015 0.015], ...
            'Box','on', 'Layer','top', 'XColor','k', 'YColor','k', ...
            'XMinorTick','on', 'YMinorTick','on', ...
            'GridColor',[0.2 0.2 0.2], 'GridAlpha',0.08, ...
            'XGrid','off', 'YGrid','on');     % 가로(거리) 그리드만 — 값 읽기 보조
end

% =========================================================================
% 로컬 서브함수: 축 상/하한을 '보기 좋은' 값으로 라운딩
%   niceCeil : +방향으로 가장 가까운 보기 좋은 값
%   niceFloor: -방향으로 가장 가까운 보기 좋은 값
% =========================================================================
function v = niceCeil(x)
    if x == 0, v = 0; return; end
    e = floor(log10(abs(x)));
    b = x / 10^e;                                    % 같은 부호, 절댓값 약 1~10
    steps = [1 1.2 1.5 2 2.5 3 4 5 6 7 8 9 10];
    if x > 0
        k = find(steps >= b - 1e-9, 1, 'first');
        v = steps(k) * 10^e;
    else
        k = find(steps <= abs(b) + 1e-9, 1, 'last');
        v = -steps(k) * 10^e;
    end
end

function v = niceFloor(x)
    v = -niceCeil(-x);
end