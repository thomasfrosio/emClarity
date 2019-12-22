function [OUT] = EMC_resize(IMAGE, LIMITS, OPTION)
% [OUT] = EMC_resize(IMAGE, LIMITS, OPTIONAL)
%
% Pad and/or crop an IMAGE.
%
% IMAGE (single | double):          2d/3d image to pad an/or crop.
%
% LIMITS (vector):                  Number of pixels to pad or crop, for each axis.
%                                   If 2d IMAGE: [xleft, xright, yleft, yright].
%                                   If 3d IMAGE: [xleft, xright, yleft, yright, zleft, zright].
%                                   See EMC_multi_limits for more details.
%                                   NOTE: Positive values indicate the number of pixels to pad, while
%                                         negative values indicate the number of pixels to crop.
%
% OPTION (cell | struct):           Optional parameters.
%                                   If cell: {field,value ; ...}, note the ';' between parameters.
%                                   NOTE: Can be empty.
%                                   NOTE: Unknown fields will raise an error.
%
%   -> 'origin' (int):              Origin convention - Center of rotation.
%                                   -1, 1 or 2; see EMC_multi_gridVectors for more details.
%                                   NOTE: 1|2 produce identical results because LIMITS is not relative
%                                         to the origin but to the edges of the IMAGE. On the other hand,
%                                         'origin'=-1 is different as it specifies a not-centered IMAGE
%                                         (zero frequency first). As such, the 'edges' of IMAGE are at
%                                         the center of the array.
%                                   NOTE: This function opperates in pixel space. As such, origin=0 is not
%                                         allowed.
%                                   defaut = 1
%
%   -> 'value' (float | str):       If float: value to pad with.
%                                   If 'uniform': pad with white gaussian noise.
%                                   If 'mean': pad with the mean of the IMAGE.
%                                   NOTE: this parameter is ignored if no padding is applied.
%                                   default = 0
%
%   -> 'taper' (bool|cell|vector):  Apply a taper to the IMAGE padded edges before padding.
%                                   If bool: Apply or not the default taper; equivalent to {'cosine', 7}
%                                   If cell: {type, size} with type = 'linear' or 'cosine' and with 
%                                   size = size of the taper (in pixel).
%                                   If vector: ROW vector used as taper (left to right <-> center to edge).
%                                   NOTE: all IMAGE dimensions should be larger than the taper, with the
%                                         exception of origin=-1 that requires the dimensions to be at
%                                         least 2 times larger than the taper.
%                                   NOTE: if the taper is a gpuArray, the IMAGE should also be a gpuArray.
%                                   default = {'cosine', 7}
%
%   -> 'force_taper' (bool):        By default, (force_taper=false) only the edges that are padded are
%                                   tapered. If true, apply the taper to every edges even if they are not
%                                   padded. If cropping is required, apply the taper AFTER cropping.
%                                   NOTE: this has no effect if 'taper' = false.
%                                   default = false
%
%   -> 'precision' (str):           Precision of the padded/cropped image; 'single' or 'double'.
%                                   default = same as IMAGE
%
%---------
% EXAMPLE:                          [OUT] = EMC_resize(randn(64,64), [10,10,-5,0], {})
%                                   [OUT] = EMC_resize(randn(64,64), [10,10,-5,0], ...
%                                                      {'value', 2; 'origin', -1})
%
% See also EMC_multi_limits.m

%% MAIN
[OPTION, flg] = checkIN(IMAGE, LIMITS, OPTION);

% Short cut: nothing to do to the IMAGE.
if ~flg.pad && ~flg.crop && ~(flg.taper && OPTION.force_taper)
    if (flg.change_precision)
        if strcmp(OPTION.precision, 'single')
            OUT = single(IMAGE);
        else  % double
            OUT = double(IMAGE);
        end
    else
        OUT = IMAGE;
    end
    return
end

% Cropping and padding are done simultaneously.
IN_size = size(IMAGE);
OUT_size = IN_size + sum(reshape(LIMITS, 2, []));

% Option to pad with white gaussian noise.
if (flg.uniform)
    val = mean(IMAGE(:));
    std_ = std(IMAGE(:));
else
    val = OPTION.value;
    std_ = nan;
end

% Allocate memory for the output image.
if (flg.gpu)
    if (flg.uniform)
       	OUT = randn(OUT_size, OPTION.precision, 'gpuArray') .* std_ + val;
    else
      	OUT = zeros(OUT_size, OPTION.precision, 'gpuArray');
        if OPTION.value ~= 0
            OUT = OUT + OPTION.value;
        end
   	end
else
  	if (flg.uniform)
       	OUT = randn(OUT_size, OPTION.precision) .* std_ + val;
    else
      	OUT = zeros(OUT_size, OPTION.precision);
        if OPTION.value ~= 0
            OUT = OUT + OPTION.value;
        end
  	end
end

x=1; y=2; z=3;
if (flg.is3d)
    if (flg.fft)  % not-centered IMAGE: 'origin' = -1
        crop = reshape(LIMITS .* (LIMITS < 0), 2, []);
        l = floor((IN_size+1) / 2) + crop(1, :);  % left side
        r = floor((IN_size-2) / 2) + crop(2, :);  % right side

        % Taper
        if (flg.taper)
            s = numel(OPTION.taper);
            pad = LIMITS > 0;

            if any(pad(1:2) > 0) || OPTION.force_taper
                t = OPTION.taper';
                tf = flip(t);
                IMAGE(l(x)-s+1:l(x), :, :)         = IMAGE(l(x)-s+1:l(x), :, :)         .*t  +val.*(1-t);
                IMAGE(end-r(x):end-r(x)+s-1, :, :) = IMAGE(end-r(x):end-r(x)+s-1, :, :) .*tf +val.*(1-tf);
            end
            if any(pad(3:4) > 0) || OPTION.force_taper
                t = OPTION.taper;
                tf = flip(t);
                IMAGE(:, l(y)-s+1:l(y), :)         = IMAGE(:, l(y)-s+1:l(y), :)         .*t  +val.*(1-t);
                IMAGE(:, end-r(y):end-r(y)+s-1, :) = IMAGE(:, end-r(y):end-r(y)+s-1, :) .*tf +val.*(1-tf);
            end
            if any(pad(5:6) > 0) || OPTION.force_taper
                t = reshape(OPTION.taper, 1, 1, []);
                tf = flip(t);
                IMAGE(:, :, l(z)-s+1:l(z))         = IMAGE(:, :, l(z)-s+1:l(z))         .*t  +val.*(1-t);
                IMAGE(:, :, end-r(z):end-r(z)+s-1) = IMAGE(:, :, end-r(z):end-r(z)+s-1) .*tf +val.*(1-tf);
            end
        end

        % Pad/Crop
        if (flg.pad || flg.crop)
            OUT(1:l(x),       1:l(y),       1:l(z))       = IMAGE(1:l(x),       1:l(y),       1:l(z));
            OUT(end-r(x):end, 1:l(y),       1:l(z))       = IMAGE(end-r(x):end, 1:l(y),       1:l(z));
            OUT(1:l(x),       end-r(y):end, 1:l(z))       = IMAGE(1:l(x),       end-r(y):end, 1:l(z));
            OUT(end-r(x):end, end-r(y):end, 1:l(z))       = IMAGE(end-r(x):end, end-r(y):end, 1:l(z));
            OUT(1:l(x),       1:l(y),       end-r(z):end) = IMAGE(1:l(x),       1:l(y),       end-r(z):end);
            OUT(end-r(x):end, 1:l(y),       end-r(z):end) = IMAGE(end-r(x):end, 1:l(y),       end-r(z):end);
            OUT(1:l(x),       end-r(y):end, end-r(z):end) = IMAGE(1:l(x),       end-r(y):end, end-r(z):end);
            OUT(end-r(x):end, end-r(y):end, end-r(z):end) = IMAGE(end-r(x):end, end-r(y):end, end-r(z):end);
        else  % force_taper without pad or crop
            if (flg.change_precision)
                if strcmp(OPTION.precision, 'single')
                    OUT = single(IMAGE);
                else  % double
                    OUT = double(IMAGE);
                end
            else
                OUT = IMAGE;
            end
        end
    else  % centered IMAGE: 'origin' = 0|1|2
        crop = abs(LIMITS .* (LIMITS < 0));
        pad  = LIMITS .* (LIMITS > 0);

        if (flg.taper) && (any(pad) || OPTION.force_taper)
            l = numel(OPTION.taper) + crop;  % broadcast
            ty = OPTION.taper;
            tx = ty';
            tz = reshape(ty, 1, 1, []);

            % top, down, left, right, bottom, front
            if pad(1) || OPTION.force_taper
                IMAGE(1+crop(1):l(1),:,:)         = IMAGE(1+crop(1):l(1),:,:) .* flip(tx) + val.*(1-flip(tx));
            end
            if pad(2) || OPTION.force_taper
                IMAGE(end-l(2)+1:end-crop(2),:,:) = IMAGE(end-l(2)+1:end-crop(2),:,:) .* tx + val.*(1-tx);
            end
            if pad(3) || OPTION.force_taper
                IMAGE(:,1+crop(3):l(3),:)         = IMAGE(:,1+crop(3):l(3),:) .* flip(ty) + val.*(1-flip(ty));
            end
            if pad(4) || OPTION.force_taper
                IMAGE(:,end-l(4)+1:end-crop(4),:) = IMAGE(:,end-l(4)+1:end-crop(4),:) .* ty + val.*(1-ty);
            end
            if pad(5) || OPTION.force_taper
                IMAGE(:,:,1+crop(5):l(5))         = IMAGE(:,:,1+crop(5):l(5)) .* flip(tz) + val.*(1-flip(tz));
            end
            if pad(6) || OPTION.force_taper
                IMAGE(:,:,end-l(6)+1:end-crop(6)) = IMAGE(:,:,end-l(6)+1:end-crop(6)) .* tz + val.*(1-tz);
            end
        end  % end taper 3d

        % Pad/Crop
        if flg.pad && flg.crop
            OUT(1+pad(1):end-pad(2), ...
                1+pad(3):end-pad(4), ...
                1+pad(5):end-pad(6)) = IMAGE(1+crop(1):end-crop(2), ...
                                                   1+crop(3):end-crop(4), ...
                                                   1+crop(5):end-crop(6));
        elseif flg.pad  % pad only
            OUT(1+pad(1):end-pad(2), 1+pad(3):end-pad(4), 1+pad(5):end-pad(6)) = IMAGE;
        elseif flg.crop  % crop only
            OUT(:,:,:) = IMAGE(1+crop(1):end-crop(2), 1+crop(3):end-crop(4), 1+crop(5):end-crop(6));
        else  % force_taper without pad or crop
            if (flg.change_precision)
                if strcmp(OPTION.precision, 'single')
                    OUT = single(IMAGE);
                else  % double
                    OUT = double(IMAGE);
                end
            else
                OUT = IMAGE;
            end
        end
    end
else  % 2d
    if (flg.fft)  % not-centered IMAGE: 'origin' = -1
        crop = reshape(LIMITS .* (LIMITS < 0), 2, []);
        l = floor((IN_size+1) / 2) + crop(1, :);  % left side
        r = floor((IN_size-2) / 2) + crop(2, :);  % right side

        % Taper.
        if (flg.taper)
            s = numel(OPTION.taper);
            pad = LIMITS > 0;
            if any(pad(1:2) > 0) || OPTION.force_taper
                t = OPTION.taper';
                tf = flip(t);
                IMAGE(l(x)-s+1:l(x), :)         = IMAGE(l(x)-s+1:l(x), :)         .*t  +val.*(1-t);
                IMAGE(end-r(x):end-r(x)+s-1, :) = IMAGE(end-r(x):end-r(x)+s-1, :) .*tf +val.*(1-tf);
            end
            if any(pad(3:4) > 0) || OPTION.force_taper
                t = OPTION.taper;
                tf = flip(t);
                IMAGE(:, l(y)-s+1:l(y))         = IMAGE(:, l(y)-s+1:l(y))         .*t  +val.*(1-t);
                IMAGE(:, end-r(y):end-r(y)+s-1) = IMAGE(:, end-r(y):end-r(y)+s-1) .*tf +val.*(1-tf);
            end
        end  % end taper 2d

        % Pad/Crop
        if (flg.pad || flg.crop)
            OUT(1:l(x),       1:l(y))       = IMAGE(1:l(x),       1:l(y));
            OUT(end-r(x):end, 1:l(y))       = IMAGE(end-r(x):end, 1:l(y));
            OUT(1:l(x),       end-r(y):end) = IMAGE(1:l(x),       end-r(y):end);
            OUT(end-r(x):end, end-r(y):end) = IMAGE(end-r(x):end, end-r(y):end);
        else  % force_taper without pad or crop
            if (flg.change_precision)
                if strcmp(OPTION.precision, 'single')
                    OUT = single(IMAGE);
                else  % double
                    OUT = double(IMAGE);
                end
            else
                OUT = IMAGE;
            end
        end
    else  % centered IMAGE: 'origin' = 0|1|2
        crop = abs(LIMITS .* (LIMITS < 0));
        pad  = LIMITS .* (LIMITS > 0);

        if (flg.taper) && (any(pad) || OPTION.force_taper)
            l = numel(OPTION.taper) + crop;  % broadcast
            ty = OPTION.taper;
            tx = ty';
            % top, down, left, right
            if pad(1) || OPTION.force_taper
                IMAGE(1+crop(1):l(1), :)        = IMAGE(1+crop(1):l(1), :) .* flip(tx) + val.*(1-flip(tx));
            end
            if pad(2) || OPTION.force_taper
                IMAGE(end-l(2)+1:end-crop(2),:) = IMAGE(end-l(2)+1:end-crop(2),:) .* tx + val.*(1-tx);
            end
            if pad(3) || OPTION.force_taper
                IMAGE(:, 1+crop(3):l(3))        = IMAGE(:, 1+crop(3):l(3)) .* flip(ty) + val.*(1-flip(ty));
            end
            if pad(4) || OPTION.force_taper
                IMAGE(:,end-l(4)+1:end-crop(4)) = IMAGE(:,end-l(4)+1:end-crop(4)) .* ty + val.*(1-ty);
            end
        end  % end taper

        if flg.pad && flg.crop  % pad and crop
            OUT(1+pad(1):end-pad(2), 1+pad(3):end-pad(4)) = IMAGE(1+crop(1):end-crop(2), ...
                                                                  1+crop(3):end-crop(4));
        elseif flg.pad  % pad only
            OUT(1+pad(1):end-pad(2), 1+pad(3):end-pad(4)) = IMAGE;
        elseif flg.crop  % crop only
            OUT(:,:) = IMAGE(1+crop(1):end-crop(2), 1+crop(3):end-crop(4));
        else  % force_taper without pad or crop
            if (flg.change_precision)
                if strcmp(OPTION.precision, 'single')
                    OUT = single(IMAGE);
                else  % double
                    OUT = double(IMAGE);
                end
            else
                OUT = IMAGE;
            end
        end
    end
end

end  % EMC_resize


function [OPTION, flg, ndim] = checkIN(IMAGE, LIMITS, OPTION)
% Standard sanity check.

% LIMITS
edges = numel(LIMITS);
if edges == 6
    flg.is3d = true;
    ndim = 3;
elseif edges == 4
    flg.is3d = false;
    ndim = 2;
else
    error('LIMITS should be of size 4 (2d) or 6 (3d), got %d', edges)
end
validateattributes(LIMITS, {'numeric'}, {'integer', 'vector'}, 'checkIN', 'LIMITS')
if ndim ~= ndims(IMAGE)
    error('IMAGE (%fD) and LIMITS (%fD) do not correspond', ndims(IMAGE), ndim)
end

if any(LIMITS > 0)
    flg.pad = true;
else
    flg.pad = false;
end

if any(LIMITS < 0)
    flg.crop = true;
else
    flg.crop = false;
end

% Extract optional parameters
OPTION = EMC_extract_option(OPTION, {'origin', 'value', 'taper', 'force_taper', 'precision'}, false);

if isfield(OPTION, 'origin')
    if OPTION.origin == -1
        flg.fft = true;
    elseif OPTION.origin == -1 || OPTION.origin == 1 || OPTION.origin == 2
        flg.fft = false;
    else
        error("origin should be 1, 2, or -1, got %d", OPTION.origin)
    end
else
    OPTION.origin = 1;  % default
    flg.fft = false;
end

if isfield(OPTION, 'value')
    if strcmpi(OPTION.value, 'uniform')
        flg.uniform = true;
    elseif strcmpi(OPTION.value, 'mean')
        OPTION.value = mean(IMAGE(:));
        flg.uniform = false;
    elseif isinteger(OPTION.value) || isfloat(OPTION.value)
        flg.uniform = false;
    else
        error("value should be a float|int or 'uniform'")
    end
else
    OPTION.value = 0;  % default
    flg.uniform = false;
end

if isfield(OPTION, 'taper')
    % bool
    if islogical(OPTION.taper)
        if OPTION.taper
            OPTION.taper = EMC_taper('cosine', 1, 0, 7);  % default
            flg.taper = true;
        else
            flg.taper = false;
        end
    % [type, size]
    elseif iscell(OPTION.taper)
        if numel(OPTION.taper) ~= 2
            error('taper not recognized.')
        else
            OPTION.taper = EMC_taper(OPTION.taper{1}, 1, 0, OPTION.taper{2});
            flg.taper = true;
        end
    % vector: own taper
    else
        validateattributes(OPTION.taper, {'numeric'}, {'row'})
        flg.taper = true;
    end
else
     OPTION.taper = EMC_taper('cosine', 1, 0, 7);  % default
     flg.taper = true;
end

% force_taper
if isfield(OPTION, 'force_taper')
    if ~islogical(OPTION.force_taper)
        error('force_taper should be a boolean, got %s', class(OPTION.force_taper))
    end
else
    OPTION.force_taper = false;  % default
end

% If no padding, no cropping and no taper, EMC_resize needs to know
% if the precision should be changed before returning output.
if isa(IMAGE, 'gpuArray')
    flg.gpu = true;
    current_precision = classUnderlying(IMAGE);
else
    flg.gpu = false;
    current_precision = class(IMAGE);
end
if isfield(OPTION, 'precision')
    if ~(strcmpi('single', OPTION.precision) || strcmpi('double', OPTION.precision))
        error("presision should be 'single' or 'double', got %s", OPTION.precision)
    end
    if strcmpi(current_precision, OPTION.precision)
        flg.change_precision = false;
    else
        flg.change_precision = true;
    end
else
    OPTION.precision = current_precision;
    flg.change_precision = false;
end

end  % checkIN
