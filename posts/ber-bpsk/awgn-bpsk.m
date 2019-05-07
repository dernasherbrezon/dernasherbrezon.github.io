x=[-5:.1:10];
y=normpdf(x, 3, 1.5);

x2=[-10:.1:5];
y2=normpdf(x2, -3, 1.5);

h = plot(x,y,x2,y2);
set(groot,'defaultAxesTickLabelInterpreter','latex');
xticks([-10,-3,0,3,10])
xticklabels({'', '$-\sqrt{E_b}$','0', '$+\sqrt{E_b}$', ''});
ylim([0 1.1]);
xlim([-10 10]);
