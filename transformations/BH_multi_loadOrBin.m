function [ IMG_OUT, iPixelHeader, iOriginHeader, imgExt ] = ...
                                        BH_multi_loadOrBin( IMG, SAMPLING,DIMENSION )
%Check to see if a cached binned image exists, either load or bin and load.
%   Switched to using imod's newstack and binvol to create binning and
%   removed inline binning from my workflow.

iPixelHeader = '';
iOriginHeader = '';
imgExt = '';
flgLoad = 0;
if SAMPLING < 0
  samplingRate = abs(SAMPLING);
  IMG_OUT = '';
else
  flgLoad = 1;
  samplingRate = SAMPLING;
end

try
  [imgPath, imgName, imgExt] = fileparts(IMG);
catch
  IMG
  error('Trouble getting fileparts for this tilt-series');
end
if isempty(imgPath)
  imgPath = '.';
end

rng('shuffle');
randIDX = randi([1,10^10],1);

if samplingRate > 1
  nameOUT = sprintf('cache/%s_bin%d%s', imgName, samplingRate,imgExt);
  doCalc = 0;
  if exist(nameOUT,'file')
    fprintf('Using cached file %s_bin%d%s\n', imgName, samplingRate,imgExt);
    [checkHeader,~] = system(sprintf('header %s > /dev/null',nameOUT));
    if (checkHeader)
      fprintf('File exists but appears to be corrupt %s_bin%d%s\n', imgName, samplingRate,imgExt);
      doCalc = 1;
    end
  else
    doCalc = 1;
  end
    
  
  if (doCalc)
  !mkdir -p cache


    switch DIMENSION
      case 3
        system(sprintf('binvol -BinningFactor %d -antialias 6 %s cache/%s_bin%d%s >  /dev/null', ...
                                  samplingRate,IMG, imgName, samplingRate,imgExt));
      case 2
        sprintf('%s',IMG)
        try
          tiltObj = MRCImage(IMG,0);
        catch
          fprintf('If you have restarted somewhere it is possible the aligned stack is not found?\n');
          fprintf('Perhaps the value for CurrentTomoCpr is not correct?\n');
          error('Could not init an MRCImage for %s in loadOrBin',IMG);
          
        end
        iHeader = getHeader(tiltObj);
        outputName = (sprintf('cache/%s_bin%d%s',imgName, samplingRate,imgExt));       
        iPixelHeader = [iHeader.cellDimensionX/iHeader.nX .* samplingRate , ...
                        iHeader.cellDimensionY/iHeader.nY .* samplingRate, ...
                        iHeader.cellDimensionZ/iHeader.nZ .* samplingRate];

        iOriginHeader= [iHeader.xOrigin ./ samplingRate, ...
                        iHeader.yOrigin ./ samplingRate, ...
                        iHeader.zOrigin ./ samplingRate];  
                      
        bpFilt = BH_bandpass3d([iHeader.nX,iHeader.nY,1],0,0,samplingRate*2,'GPU',1);
        binSize = floor([iHeader.nX,iHeader.nY]./samplingRate);
        binSize = binSize - 1 + mod(binSize,2);
        trimVal = BH_multi_padVal([iHeader.nX,iHeader.nY],binSize);
        % For even sized images, IMODs origin of rotation is not centered on a
        % pixel, so force to ODD size to make things predicatible.
        binSize = [binSize,iHeader.nZ];
        newStack = zeros(binSize,'single');
        for iPrj = 1:binSize(3)
          iProjection = gpuArray(getVolume(tiltObj,[-1],[-1],iPrj));
          iProjection = fftn(iProjection).*bpFilt;
          iProjection = real(ifftn(ifftshift(BH_padZeros3d(fftshift(iProjection),...
                                             trimVal(1,:),trimVal(2,:),'GPU','single'))));
          newStack(:,:,iPrj) = gather(iProjection);
        end
        
        SAVE_IMG(MRCImage(newStack),outputName,iPixelHeader,iOriginHeader);
        clear newStack bpFilt iProjection
%        system(sprintf('newstack -shrink %d -antialias 6 %s cache/%s_bin%d%s > /dev/null', ...
%                                     samplingRate,IMG, imgName, samplingRate,imgExt));
      otherwise
        error('DIMENSION should be 2 or 3\n.')
    end
 
    
    

  end  
 
  
  if (flgLoad)
    failedLoads = 0;
    while failedLoads < 3
      try
        fprintf('pwd is %s\n', pwd);
        fprintf(...
           'attempting to load cache/%s_bin%d%s\n', imgName, samplingRate,imgExt);
        m = MRCImage(sprintf(...
                          'cache/%s_bin%d%s', imgName, samplingRate,imgExt));
        fprintf('Loaded the MRCImage\n');
        IMG_OUT =getVolume(m);
        fprintf('Loaded the volume\n');
        IMG_OUT = single(IMG_OUT);
        fprintf('Volume --> single\n');
        failedLoads = 3;
      catch
        failedLoads = failedLoads + 1
        pause(failedLoads.^3); % 1,8,27 second pauses
      end
    end
  end
else
  % So you could pass a -1 as sampling which would indicate to not load but that
  % syntax is only intended when resampling is required, so ignore the flag here
  % but throw a warning.
  fprintf('\n\nYou requested a sampling of -1 Nonsense!! loading anyway.\n\n');
 
  IMG_OUT = single(getVolume(MRCImage(IMG)));
end


             
end

