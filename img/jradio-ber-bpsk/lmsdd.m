Eb_N0_dB = [0:0.1:10];
theoryBer = 0.5*erfc(sqrt(10.^(Eb_N0_dB/10)));
semilogy(Eb_N0_dB,theoryBer,'b.-');
hold on;
practice = [ 0.07578894658678967 0.07308067319088958 0.0720011185883895 0.0728253137973678 0.07023935329178325 0.06890742785670688 0.06808839217814047 0.06670257329741336 0.06569756752545207 0.0642218809770734 0.06324772978426944 0.061095400877882275 0.060448696515699674 0.058599265932599266 0.05746147863193963 0.055958460878310246 0.053947212123153475 0.053098787565143725 0.05262427335232577 0.050210459407110074 0.048844954194561 0.04721371655387133 0.04559143896555947 0.044602290074043524 0.04238304397962779 0.04069974818327933 0.039125518306344864 0.03761055155491225 0.036165745919030934 0.03427453461287058 0.034491917140387074 0.03244421710758783 0.030230518905272934 0.029440400984844618 0.028856154161081955 0.02769333281281646 0.025915567491852743 0.026813459098217862 0.025137294666937603 0.02172006802755136 0.019972999855523203 0.018889924361557692 0.019523553555347125 0.01948785143647642 0.018961328599299103 0.015213773944193251 0.01645850996706396 0.0184845217968109 0.017617994668706026 0.018328533567165527 0.011974557402167019 0.008234176537301541 0.007595876038239305 0.006984936041489199 0.006422377420778834 0.01019979506316439 0.005392688272788212 0.0049185507875987525 0.004473442128033137 0.0041097476460792235 0.0037190263264755235 0.0033780210415609367 0.003082727815387346 0.0027937742177982735 0.0025331821165083595 0.007804583284534876 0.0020413604042147184 0.001820140733081283 0.0016045933612076793 0.0014230797848930655 0.001269594040215267 0.0011087676729659218 9.59953233560926E-4 8.538478709358393E-4 7.574187835187007E-4 6.93355168348837E-4 6.032657095162163E-4 5.221851965668575E-4 4.401036896304697E-4 3.933906369024441E-4 3.3733497362881343E-4 3.0029819610873597E-4 2.4924750277025085E-4 2.0820674930205693E-4 1.711699717819795E-4 1.4914810406733886E-4 1.2412325439161088E-4 1.1010933857320319E-4 9.309244079370816E-5 8.108051294935872E-5 0.0011244499120960448 5.1050693338485116E-5 4.304274144225216E-5 3.703677752007744E-5 7.744356812981958E-4 7.057007608555296E-4 6.403024870362937E-4 5.7623887186643E-4 5.151782386576537E-4 4.7013350924134334E-4 4.267571031367481E-4];
semilogy(Eb_N0_dB,practice,'r.-');
hold off;
axis([0 10 10^-5 0.5]);
grid on
xlabel('E_b/N_0, dB');
ylabel('Bit Error Rate');