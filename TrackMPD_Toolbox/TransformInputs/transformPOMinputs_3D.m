function transformPOMinputs_3D(conf_name,confOGCM_name)

% TRANSFORM OGCM outputs (SARCCM POM version) TO TrackMPD FORMAT


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% INPUTS (SARCCM POM version)
% POM output files
% hmin (depth for land)

%%%% OUTPUTS
% grid.mat
% timestamps.mat
% One file for each time step containing u,v,w,E,depth,time,time_str

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% 	$Id: transformFVCOMoutputs July 2019 Z ijalonrojas $
%
% Copyright (C) 2017-2019 Isabel Jalon-Rojas and Erick Fredj
% Licence: GPL (Gnu Public License)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Call the model configuration and inputs files

conf=feval(conf_name);
confOGCM=feval(confOGCM_name); %IJR new input format
conf=mergeStructure(conf,confOGCM); %IJR new input format

POM_Prefix = conf.OGCM.POM_Prefix;
POM_Suffix = conf.OGCM.POM_Suffix;
fnames=getAllFiles(conf.OGCM.BaseDir,strcat(POM_Prefix,'*',POM_Suffix),true);

% TO AVOID MEMORY PROBLEMS: we will save one output file with the new format 
% for each OGCM model time step (the OGCM model time step is defined inside conf)


%% Define model parameters (SARCCM POM Version)

t0=conf.OGCM.t0; %POM reference time variable (first time step)
Hmin =conf.OGCM.Hmin; %H for land

TimeStamps = 1:numel(fnames);
nTimeStamps=length(TimeStamps);
tstep=conf.OGCM.TimeStep;


%% Read and save the Grid info    

ncfile = fnames{1};

Lat = double(ncread(ncfile,'latitude'));      % units = 'degrees_north'
Lon = double(ncread(ncfile,'longitude'));     % units = 'degrees_east'

%Define boundaries of the new grid
if strcmpi(conf.OGCM.cut,'yes')
    
    fprintf('cutting grid\n');
    minLon = conf.OGCM.minLon; % min lon
    maxLon = conf.OGCM.maxLon; % max lon
    minLat = conf.OGCM.minLat; % min lat
    maxLat = conf.OGCM.maxLat; % max lat

    posLat=find(Lat>=minLat & Lat<=maxLat);
    posLon=find(Lon>=minLon & Lon<=maxLon);
    
    Lat=Lat(posLat);
    Lon=Lon(posLon);
    
    pos1Lat=posLat(1); posEndLat=posLat(end);
    pos1Lon=posLon(1); posEndLon=posLon(end);
else
    pos1Lat=1; posEndLat=length(Lat);
    pos1Lon=1; posEndLon=length(Lon);
    
end


lvl = double(ncread(ncfile,'level'));         % units = 'm'.
BottomDepth = double(ncread(ncfile,'depth'));           % units = 'm'
BottomDepth = BottomDepth(pos1Lon:posEndLon,pos1Lat:posEndLat);

% Sigma coordinate (POM)
Z=[0; cumsum(lvl(1:end-1))]; %SARCCM version 
KB = size(Z,1);
ZZ=-0.5*(Z(1:KB-1)+Z(2:KB));
ZZ(KB)=2*ZZ(KB-1)-ZZ(KB-2);


% (water/land) mask
mask = double(BottomDepth~=1);
i=BottomDepth<Hmin;
BottomDepth(i)=Hmin;
mask2=~i;
mask=double(mask & mask2);
mask_water = mask;
mask_water(mask_water~=0)=1;
%mask_land = ~mask_water;

% mask_land3D = mask_land;
% for i=1:length(lvl)-1
%     mask_land3D = cat(3,mask_land3D,mask_land);
% end

%BottomDepth(mask_land)=NaN;


%% Read and save the variables varing with time

[numlon,numlat] = size(BottomDepth);
numlvl = length(lvl);

zeros_matrix=zeros(numlon,numlat,1);

   ZZ=[0;ZZ]; %Add a layer for surface z=0 (depth(:,:,1)==E) to avoid 
   %problem when interpolating velocities near the surface

for n=1:nTimeStamps
    
    ncfile = fnames{TimeStamps(n)};
    
% Velocity and elevation
    
    u_aux = double(ncread(ncfile,'u-velocity'));      % units = 'm/s'
    v_aux = double(ncread(ncfile,'v-velocity'));      % units = 'm/s'
    w = double(ncread(ncfile,'w-velocity'));      % units = 'm/s'  
    E = double(ncread(ncfile,'elevation'));       % units = 'm'
    
    
%     %Include nans in land grid points
%     u_aux(mask_land3D) = NaN;
%     v_aux(mask_land3D) = NaN;
%     w(mask_land3D) = NaN;
%     E(mask_land) = NaN;
    
    % Conversion from Arakawa C-grid to A-grid (IJR 21/05/2018)
    u=cat(1,u_aux(2,:,:),(u_aux(2:end-1,:,:)+u_aux(3:end,:,:))/2,u_aux(end,:,:)); 
    v=cat(2,v_aux(:,2,:),(v_aux(:,2:end-1,:)+v_aux(:,3:end,:))/2,v_aux(:,end,:));

    % We can also use the functions, but I guess it will take more
    % computational time
%     u=pom_rho3u_3d(u_aux,0);
%     v=pom_rho3v_3d(v_aux,0);

    % Cut at grid size
    u=u(pos1Lon:posEndLon,pos1Lat:posEndLat,:);
    v=v(pos1Lon:posEndLon,pos1Lat:posEndLat,:);
    w=w(pos1Lon:posEndLon,pos1Lat:posEndLat,:);
    E=E(pos1Lon:posEndLon,pos1Lat:posEndLat);
        
%Time
    time = t0+(TimeStamps(n)-1)*tstep;
    time_str = datestr(time,'dd-mmm-yyyy HH:MM:SS');
    timestamps(n)=time;
    
    fprintf('changing format for time %s\n',time_str);
    
% Depth at each grid point 

    % MODIFIED BY MARIEU 2025/01 for interpolation close to the shore
    %BottomDepth(BottomDepth==1)=NaN;
    %E(E==0)=NaN;
    
    depth=nan(numlon,numlat,numlvl+1);
    for i=1:length(ZZ)
        depth(:,:,i)=ZZ(i)*(BottomDepth+E)+E;
       
        % OLD REFERENCE SYSTEM REMOVED BY V. MARIEU, 2024/09/10
        %depth(:,:,i)=depth(:,:,i)-E; % We change the reference system:
                              %Surface: depth=0, bottom changing with tide
    end
    
    % MODIFIED BY MARIEU 2025/01 for interpolation close to the shore
    depth(isnan(depth))=1;
    E(isnan(E))=0;
    
    % The velocity at the new first layer depth=0 equal to the veloctitie at
    % the old first sigma layer
       
    u=cat(3,u(:,:,1),u);
    v=cat(3,v(:,:,1),v);
    w=cat(3,w(:,:,1),w);

    %(for POM-SARCCM it's not necessary to include a bottom layer 
    %with vel=0, but in other models it may be needed)
%     depth=cat(3,zeros_matrix,depth,BottomDepth); 
%     u=cat(3,u(:,:,1),u,zeros_matrix);
%     v=cat(3,v(:,:,1),v,zeros_matrix);
%     w=cat(3,w(:,:,1),w,zeros_matrix);
    
    u=permute(u,[2,1,3]); %lat,lon,z
    v=permute(v,[2,1,3]); %lat,lon,z
    w=permute(w,[2,1,3]); %lat,lon,z
    depth=permute(depth,[2,1,3]); %lat,lon
    E=permute(E,[2,1]);
    
    % From m/s to cm/s
    
    u=u*100;
    v=v*100;
    w=w*100;
    
    save([conf.Data.BaseDir '\TrackMPDInput' num2str(n) '.mat'],'u','v','w','E','time','time_str','depth');

    
end

BottomDepth=permute(BottomDepth,[2,1]); %lat,lon
mask_water=permute(mask_water,[2,1]); %lat,lon

%save grid and time stamps
save([conf.Data.BaseDir '\grid.mat'],'Lat','Lon','BottomDepth','mask_water');
save([conf.Data.BaseDir '\timestamps.mat'],'timestamps');
fprintf('saving grid and timestamps\n');

