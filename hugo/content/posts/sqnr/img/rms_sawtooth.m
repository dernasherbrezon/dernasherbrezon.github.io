T = 10*(1/50);
fs = 1000;
t = 0:1/fs:T-1/fs;
x = sawtooth(2*pi*50*t);
plot(t,x)
 
set(groot,'defaultAxesTickLabelInterpreter','latex');
yticks([-1,0,1])
yticklabels({'-q','0','q'});
ylim([-1.2 1.2]);