c=[-1 1];
M = length(c);
data = randi([0 M-1],2000,1);
modData = genqammod(data,c);
rxSig = awgn(modData,20,'measured');
h = scatterplot(rxSig);
hold on
scatterplot(c,[],[],'r*',h)
grid
hold off