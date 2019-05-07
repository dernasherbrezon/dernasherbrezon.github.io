Eb_N0_dB = [-3:0.1:10];
theoryBer = 0.5*erfc(sqrt(10.^(Eb_N0_dB/10)));
semilogy(Eb_N0_dB,theoryBer,'b.-');
axis([-3 10 10^-5 0.5]);
grid on
xlabel('E_b/N_0, dB');
ylabel('Bit Error Rate');