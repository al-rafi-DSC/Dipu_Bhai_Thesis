close all; clear all; clc;

%% DATA ACQUISITION FROM EXCEL

filename = 'RAFT-violino-P.xlsx';

dates = datetime(2025,9,4):datetime(2025,10,5);
sheets = cellstr(datestr(dates,'yyyymmdd'));
cols = [4,6,7,10,11,12,13,14,16,18];

for k = 1:numel(sheets)
    [~,~,raw] = xlsread(filename, sheets{k});
    tmp = raw(6:end, cols);
    Data{k} = cellfun(@(x) double(string(x)), tmp);
    Data{k}(isnan(Data{k})) = NaN;
    Data{k}(:,11) = day(dates(k));
    Data{k}(:,12) = month(dates(k));
end

disp('-- DATA ACQUISITION COMPLETED --');

%% DATA FORMATTING

Data_all = vertcat(Data{:});
Data1 = Data_all(:,[1:3,11,12]);
Data2 = Data_all(:,[4:8,11,12]);
Data3 = Data_all(:,[9:10,11,12]);

Data1_p = removeNaNrows(Data1,1);
Data2_p = removeNaNrows(Data2,1);
Data3_p = removeNaNrows(Data3,2);

%Data1_p = Data1(~isnan(Data1(:,1)), :);
%Data2_p = Data2(~isnan(Data2(:,1)), :);
%Data3_p = Data3(~isnan(Data3(:,2)), :);

[tVec1,t1] = sumtime(Data1_p(:,1),Data1_p(:,4),Data1_p(:,5));
[tVec2,t2] = sumtime(Data2_p(:,1),Data2_p(:,6),Data2_p(:,7));
[tVec3,t3] = sumtime(Data3_p(:,2),Data3_p(:,3),Data3_p(:,4));

% Original signals
T_s_orig = Data1_p(:,3);
Q_orig   = -Data1_p(:,2);

T_amb_orig = Data2_p(:,2);
RH_orig    = Data2_p(:,3)/100;
v_orig     = Data2_p(:,4);
G_orig     = Data2_p(:,5);

T_sky_orig = Data3_p(:,1);


% Signals without duplicates

[tVec1u, ia1] = unique(tVec1, 'stable');
[tVec2u, ia2] = unique(tVec2, 'stable');
[tVec3u, ia3] = unique(tVec3, 'stable');

T_s_u = T_s_orig(ia1);
Q_u   = Q_orig(ia1);

T_amb_u = T_amb_orig(ia2);
RH_u    = RH_orig(ia2);
v_u     = v_orig(ia2);
G_u     = G_orig(ia2);

T_sky_u = T_sky_orig(ia3);

Q_old = Q_u;


% Applying moving average

movsetting = 20;

T_s_u = movmean(T_s_u,movsetting);
Q_u   = movmean(Q_u,movsetting);

T_amb_u = movmean(T_amb_u,movsetting);
RH_u    = movmean(RH_u,movsetting);
v_u     = movmean(v_u,movsetting);
G_u     = movmean(G_u,movsetting);

T_sky_u = movmean(T_sky_u,movsetting);


%% DATA RE-SAMPLING

tmin = max([tVec1u(1), tVec2u(1), tVec3u(1)]);
tmax = min([tVec1u(end), tVec2u(end), tVec3u(end)]);
if tmax <= tmin
    error('No overlapping time range between datasets.');
end

dt = 5*60; % Re-sampling time: 5 min

t_common = ((ceil(tmin/dt)*dt):dt:tmax)';

T_s_r = interp1(tVec1u, T_s_u, t_common, 'linear', NaN);
Q_r  = interp1(tVec1u, Q_u,   t_common, 'linear', NaN);

T_amb_r = interp1(tVec2u, T_amb_u, t_common, 'linear', NaN);
RH_r    = interp1(tVec2u, RH_u,    t_common, 'linear', NaN);
v_r     = interp1(tVec2u, v_u,     t_common, 'linear', NaN);
G_r     = interp1(tVec2u, G_u,     t_common, 'linear', NaN);

T_sky_r = interp1(tVec3u, T_sky_u, t_common, 'linear', NaN);


% NaN removal

valid = ~(isnan(T_s_r) | isnan(Q_r) | isnan(T_amb_r) | isnan(RH_r) | isnan(v_r) | isnan(G_r) | isnan(T_sky_r));
t_common = t_common(valid);


% Final, full data (in the correct unit of measure)

T_s_full   = T_s_r(valid) + 273.15;
Q_full     = Q_r(valid);
T_amb_full = T_amb_r(valid) + 273.15;
RH_full    = RH_r(valid);
v_full     = v_r(valid);
G_full     = G_r(valid);
T_sky_full = T_sky_r(valid) + 273.15;


%% SEPARATION IN TRAINING/VALIDATION SET

%{
N = length(Q_full);
Nval = round(0.05*N);

val_idx = randperm(N, Nval);
train_idx = setdiff(1:N, val_idx);

% Validation data
T_s_val   = T_s_full(val_idx);
Q_val     = Q_full(val_idx);
T_amb_val = T_amb_full(val_idx);
RH_val    = RH_full(val_idx);
v_val     = v_full(val_idx);
G_val     = G_full(val_idx);
T_sky_val = T_sky_full(val_idx);

% Training data
T_s   = T_s_full(train_idx);
Q     = Q_full(train_idx);
T_amb = T_amb_full(train_idx);
RH    = RH_full(train_idx);
v     = v_full(train_idx);
G     = G_full(train_idx);
T_sky = T_sky_full(train_idx);

disp('Data pre-processing completed');
%}

%% NEURAL NETWORK TRAINING & OPTIMIZATION

% Normalization

x1 = T_s_full; x2 = RH_full; x3 = G_full; x4 = v_full; x5 = T_sky_full; y = Q_full;
Xall = [x1 x2 x3 x4 x5]'; Yall = y';

[XallN, psX] = mapminmax(Xall);
[YallN, psY] = mapminmax(Yall);

disp('-- DATA PRE-PROCESSING COMPLETED --');

% Cross validation

K = 5;
cv = cvpartition(size(XallN,2),'KFold',K);


% Hyperparameters definition
disp('-- HYPERPARAMETER OPTIMIZATION STARTED --');

netTypes = {'trainlm','trainbr','trainscg'};
%netTypes = {'trainbr'};

hiddenLayers = {[5] [10] [20] [10 5] [20 10]};
%hiddenLayers = {2 5 10 20};

transferFcns = {'tansig','logsig'};

results = [];

bestRMSE = inf;


% Hyperparameter tuning

for iType = 1:length(netTypes)

    for iLayer = 1:length(hiddenLayers)

        for iTF = 1:length(transferFcns)

            foldRMSE = zeros(K,1);

            for k = 1:K

                trainIdx = training(cv,k);
                valIdx   = test(cv,k);

                Xtr = XallN(:,trainIdx);
                Ytr = YallN(:,trainIdx);

                Xva = XallN(:,valIdx);
                Yva = YallN(:,valIdx);


                net = fitnet(hiddenLayers{iLayer});

                net.trainFcn = netTypes{iType};

                for h = 1:length(net.layers)-1
                    net.layers{h}.transferFcn = transferFcns{iTF};
                end

                net.divideFcn = 'dividetrain';

                net.trainParam.showWindow = false;
                net.trainParam.showCommandLine = false;


                net = train(net,Xtr,Ytr);


                YpredN = net(Xva);

                Ypred = mapminmax('reverse',YpredN,psY);
                Ytrue = mapminmax('reverse',Yva,psY);

                foldRMSE(k) = sqrt(mean((Ypred - Ytrue).^2));

            end

            meanRMSE = mean(foldRMSE);
            stdRMSE  = std(foldRMSE);

            results = [results;
                {netTypes{iType}, ...
                 mat2str(hiddenLayers{iLayer}), ...
                 transferFcns{iTF}, ...
                 meanRMSE, ...
                 stdRMSE}];

            fprintf('Fcn=%s Layers=%s TF=%s RMSE=%.4f\n',...
                netTypes{iType},...
                mat2str(hiddenLayers{iLayer}),...
                transferFcns{iTF},...
                meanRMSE);

            if meanRMSE < bestRMSE

                bestRMSE = meanRMSE;

                bestConfig.trainFcn = netTypes{iType};
                bestConfig.layers = hiddenLayers{iLayer};
                bestConfig.transferFcn = transferFcns{iTF};

            end

        end
    end
end

disp('-- HYPERPARAMETER OPTIMIZATION COMPLETED --\n');




%{
NN = fitnet(10);     % 10 hidden neurons

NN.divideFcn = 'divideind';

nTrain = size(Xtrain,2);
nVal   = size(Xval,2);

Xall = [Xtrain Xval];
Yall = [Ytrain Yval];

NN.divideParam.trainInd = 1:nTrain;
NN.divideParam.valInd   = nTrain+1:nTrain+nVal;
NN.divideParam.testInd  = [];

NN = train(NN,Xall,Yall);
disp('NN training completed');

Ypred = NN(Xval);
rmse = sqrt(mean((Ypred - Yval).^2));
disp('NN prediction ended');

%}

%% RESULTS

% Results of hyperparameter tuning

fprintf('\n --- BEST CONFIGURATION --- \n');
fprintf('Training algorithm : %s\n', bestConfig.trainFcn);
fprintf('Layers             : %d\n', bestConfig.layers);
fprintf('Transfer function  : %s\n', bestConfig.transferFcn);
fprintf('Mean RMSE (CV)     : %.2f\n', bestRMSE);


% Training of the best model

netFinal = fitnet(bestConfig.layers);
netFinal.trainFcn = bestConfig.trainFcn;
netFinal.divideFcn = 'dividetrain';

netFinal.trainParam.showWindow = false;
netFinal.trainParam.showCommandLine = true;

netFinal = train(netFinal,XallN,YallN);

YpredN = netFinal(XallN);

Ypred = mapminmax('reverse',YpredN,psY);
Ytrue = mapminmax('reverse',YallN,psY);


% Display results

results = evaluate_model(Ytrue, Ypred);


scatter(Ytrue, Ypred, 30, [0.647, 0.247, 0.361], 'filled', 'MarkerFaceAlpha', 0.7); hold on;

xlim([-40 100]);
ylim([-40 100]);
xticks(-40:20:100);
yticks(-40:20:100);

l = linspace(-40,100,200);
plot(l,l,'k--','LineWidth',1);        
axis square;
xlabel('Measured Q_{net} (W m^{-2})','FontSize',20);
ylabel('Predicted Q_{net}^* (W m^{-2})','FontSize',20);

title(sprintf('Measured vs Predicted (R^2 = %.2f)', results.R2),'FontSize',20);
set(gca,'FontSize',20);
grid off; box on;
hold off;
%}





%% CHECKING CORRELATIONS


%x1_mean = mean(x1);
%x2_mean = mean(x2);
%x3_mean = mean(x3);
%x4_mean = mean(x4);
%x5_mean = mean(x5);

%x1_range = linspace(min(x1),max(x1),100);
%x5_range = linspace(-50,20,100)+273.15;
%x2_range = linspace(min(x2),max(x2),100);
%x3_range = linspace(0,1000,100);

%{
Xp = [ ...
    repmat(x1_mean,1,length(x5_range));
    repmat(x2_mean,1,length(x5_range));
    repmat(x3_mean,1,length(x5_range));
    repmat(x4_mean,1,length(x5_range));
    x5_range];
%}

%{
Xp = [ ...
    x1_range;
    repmat(x2_mean,1,length(x1_range));
    repmat(x3_mean,1,length(x1_range));
    repmat(x4_mean,1,length(x1_range));
    repmat(x5_mean,1,length(x1_range));
    ];
%}

%{
Xp = [ ...
    repmat(x1_mean,1,length(x2_range));
    x2_range;
    repmat(x3_mean,1,length(x2_range));
    repmat(x4_mean,1,length(x2_range));
    repmat(x5_mean,1,length(x2_range));
    ];
%}

%XpN = mapminmax('apply',Xp,psX);

%QpredN = netFinal(XpN);

%Qpred = mapminmax('reverse',QpredN,psY);




%{
%% PHYSICAL MODEL COMPARISON

WF = 0.94;
SAF = 0/100;
correction_eps = 0.958*0.95; % angular=0.958 % error = 0.95

definition = 10000;
lambda = (linspace(1e-12,1e-3,definition));

eps_p=[];
for i=1:definition
    eps_p(i) = eps_spacecool(lambda(i)*10^6);
end

for i=1:length(x2_range)
    [Q_sol(i),Q_atm(i),T_sky_sim(i),dwlwar_sim(i)] = panel_thermalbalance_speed_atmosphere_corrected_full(x1_mean,x2_range(i),x3_mean,lambda,eps_p,WF,SAF,correction_eps);
    Q_p(i) = (panel_solver(x1_mean,lambda,eps_p,correction_eps))';
    QpredSIM(i) = Q_p(i) - Q_sol(i) - Q_atm(i); 
end

x5_range = T_sky_sim;


Xp = [ ...
    repmat(x1_mean,1,length(x2_range));
    x2_range;
    repmat(x3_mean,1,length(x2_range));
    repmat(x4_mean,1,length(x2_range));
    x5_range;
    ];

XpN = mapminmax('apply',Xp,psX);

QpredN = netFinal(XpN);

Qpred = mapminmax('reverse',QpredN,psY);

plot(x2_range,Qpred,x2_range,QpredSIM);
%}



%}

%{
if ~isempty(t1)
    baseDates = dateshift(t1(1),'start','day');
    tVecDays = seconds(timeofday(t1(1)));
    % Build datetime for each common time by adding seconds to the base date
    t = baseDates + seconds(t_common);
else
    t = [];
end

%}


function metrics = evaluate_model(Q_true, Q_pred)

    Q_true = Q_true(:);
    Q_pred = Q_pred(:);

    metrics.RMSE = sqrt(mean((Q_true - Q_pred).^2));
    metrics.MAE  = mean(abs(Q_true - Q_pred));

    SS_res = sum((Q_true - Q_pred).^2);
    SS_tot = sum((Q_true - mean(Q_true)).^2);
    metrics.R2 = 1 - SS_res/SS_tot;

    metrics.MAPE = mean(abs((Q_true - Q_pred) ./ Q_true)) * 100;

end

function [Q_p] = panel_solver(T_p,lambda,eps_p,correction_eps)

h = 6.6261*10^(-34); %[J s] Plank's constant
c = 299792458; %[m/s] Speed of light in vacuum
k_B = 1.3806*10^(-23); %[J/K] Boltzmann's constant
A = 1; %[m^2] Panel area (all calculations refer to 1m^2)

LAMBDA = lambda*(1e+6);

for j = 1:length(eps_p)
 if LAMBDA(j) >= 7.1 || LAMBDA(j) <= 13
        eps_p_ang(j) = eps_p(j)*correction_eps;
 end
 end


for i=1:length(T_p)
    
    I_BB_p = ((2*h*c^2)./(lambda.^5)).*(1./(exp((h.*c)./(lambda.*k_B.*T_p(i))) -1)); %[W/m^3/sr] Black body emission
    I_BB_p(1) = 0;

    Integral1_p = eps_p_ang.*I_BB_p;
    Area_Integral1_p = trapz(lambda,Integral1_p);

    Integtral2_p = @(theta) sin(2*theta);
    Area_Integral2_p = integral(Integtral2_p,0,pi/2);

    Q_p_x(i) = A*pi*Area_Integral1_p*Area_Integral2_p; % [W/m^2]
end

Q_p = Q_p_x';

end

function Q_pred = predict_Q(mdl_main, x1, x2, x3, x5)

    x1 = x1(:);
    x2 = x2(:);
    x3 = x3(:);
    x5 = x5(:);


    % --- Step 2: build corrected output ---
    Qstar_pred = predict(mdl_main, table(x1, x2, x5));

    % --- Step 3: reconstruct original Q ---
    Q_pred = Qstar_pred + Q_x3;

end


function x_norm = normalize_signal(x)
    mu = mean(x);
    sigma = std(x);

    if sigma == 0
        x_norm = x - mu;  % all zeros if constant signal
    else
        x_norm = (x - mu) / sigma;
    end
end


function [alpha] = solar_absorptivity_calculator()

    irradiance_data = readmatrix("irradiance_AM15_ASTM.txt");
    lambda_irr = irradiance_data(:,1); % [nm]
    irradiance_AM15 = irradiance_data(:,2); % [W/m^2/nm]
    eps_p_irr=[];
    for i=1:length(lambda_irr)
        eps_p_irr(i) = eps_spacecool(lambda_irr(i)/1000);
        prod_irr(i) = eps_p_irr(i)*irradiance_AM15(i); 
    end
    alpha = trapz(lambda_irr/1000,prod_irr)/trapz(lambda_irr/1000,irradiance_AM15);

end


function Data_clean = removeNaNrows(Data,n)

    % Find rows where column n is NOT NaN
    validRows = ~isnan(Data(:,n));

    % Keep only valid rows across all columns
    Data_clean = Data(validRows, :);

end

function [tVec,t] = sumtime(F,d,m)

    t_ = datetime(F, 'ConvertFrom','excel','Format','HH:mm:ss');
    t = datetime(2025, d, m, hour(t_), minute(t_), second(t_));
    tsec = seconds(timeofday(t));
    reset = [false; diff(tsec) < 0];
    offset = cumsum(reset .* [0; tsec(1:end-1)]);
    tVec = tsec + offset;

end


function [m, b, R2] = linearRegressionPlot(x, y)

    % Ensure column vectors
    x = x(:);
    y = y(:);

    % Remove NaN values
    valid = ~(isnan(x) | isnan(y));
    x = x(valid);
    y = y(valid);

    % Linear regression: y = m*x + b
    p = polyfit(x, y, 1);
    m = p(1);
    b = p(2);

    % Predicted values
    y_fit = polyval(p, x);

    % Calculate R^2
    SS_res = sum((y - y_fit).^2);
    SS_tot = sum((y - mean(y)).^2);
    R2 = 1 - SS_res / SS_tot;

    % Plot
    figure;
    scatter(x, y, 50, 'filled');
    hold on;

    % Sort x for a clean line
    [x_sorted, idx] = sort(x);
    plot(x_sorted, y_fit(idx), 'r-', 'LineWidth', 2);

    xlabel('x');
    ylabel('y');
    title(sprintf('Linear Regression (R^2 = %.4f)', R2));
    legend('Data', 'Linear Fit', 'Location', 'best');
    grid on;
    hold off;

    % Display results
    fprintf('Slope (m)     = %.6f\n', m);
    fprintf('Intercept (b) = %.6f\n', b);
    fprintf('R^2           = %.6f\n', R2);

end