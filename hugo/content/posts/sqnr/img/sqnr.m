x = [8 10 12 16 24];
y = 20*log10(2.^x*sqrt(3/2));
scatter(x,y)
ylim([0 150]);
xlim([0 30]);
xlabel('Number of bit')
ylabel('db')