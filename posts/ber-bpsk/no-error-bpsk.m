x=[-5 5];
y=[1 1];

h = plot(x,y,'o','MarkerSize',5, 'MarkerFaceColor', 'b');
set(groot,'defaultAxesTickLabelInterpreter','latex');
xticks([-10,-5,0,5,10])
xticklabels({'', '$-\sqrt{E_b}$','0', '$+\sqrt{E_b}$', ''});
ylim([0 1.1]);
xlim([-10 10]);
