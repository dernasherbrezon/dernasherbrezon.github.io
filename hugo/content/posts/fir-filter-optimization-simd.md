---
title: "Ускорение работы FIR фильтра с помощью SIMD NEON"
date: 2023-06-25T21:20:18+01:00
draft: false
chartjs: true
tags:
  - raspberrypi
  - C
  - SIMD
  - производительность
---

Уже которую неделю я пытаюсь добавить поддержку [airspy mini](https://airspy.com/airspy-mini/) в [sdr-server](https://github.com/dernasherbrezon/sdr-server). На этот раз я упёрся в производительность Raspberrypi. При получении сигнала один клиент загружал одно ядро на 80%. Это значит, что sdr-server способен обработать только ~4 параллельных наблюдения. Я скомпилировал и запустил утилиту perf, которая показала интересное - большинство времени тратится внутри драйвера к airspy. На самом деле, там происходит много сложных DSP операций:

```C
static void remove_dc(iqconverter_float_t *cnv, float *samples, int len)
{
	int i;
	ALIGNED float avg = cnv->avg;

	for (i = 0; i < len; i++)
	{
		samples[i] -= avg;
		avg += SCALE * samples[i];
	}

	cnv->avg = avg;
}
```

Из-за больших скоростей сэмплирования, процессор должен обрабатывать очень много данных перед тем, как выдать пользователю. Из хороших новостей: если поглядеть в [исходные коды](https://github.com/airspy/airspyone_host/blob/master/libairspy/src/iqconverter_float.c#L466), то можно увидеть оптимизации для SSE2. То есть в принципе авторы старались оптимизировать код с помощью [интристиков](https://developer.arm.com/architectures/instruction-sets/simd-isas/neon/intrinsics?search=vld1q_s8). Из плохих новостей: поддержки ARM нет. Однако, есть [одинокий pull request](https://github.com/airspy/airspyone_host/pull/89) в котором добавлена поддержка NEON и утверждается, что добавление SIMD ускоряет код всего лишь на 4~8%. Мне показалось это странным, так как [в одной из моих статей](https://dernasherbrezon.com/posts/simd-for-dsp/) я своими глазами видел ускорение в 2 раза.

## ARM-TESTS

Операция свёртки настолько стандартная, что моей первой мыслью было поискать бенчмарки в Интернете. Но я ничего не нашёл! Тогда я вздохнул и решил написать свои. Так и получился проект [arm-tests](https://github.com/dernasherbrezon/arm-tests). Идея проекта заключается в том, чтобы проверить выполнение одной и той же операции в разных условиях. Для этого я очень активно использовал директивы препроцессора и cmake. С помощью последнего я смог создать очень много маленьких исполняемых файлов, которые удобно выполнять в любой комбинации и сравнивать результаты.

```cmake
foreach(TEST_TYPE TEST_GENERIC TEST_NEON4Q TEST_NEON2Q TEST_NEON1Q)
    foreach(TEST_MEMORY TEST_ALIGN_MEMORY TEST_NONALIGN_MEMORY)
        foreach(TEST_SIZE TEST_ALIGN_SIZE TEST_NONALIGN_SIZE)
            foreach(TEST_FETCH TEST_PREFETCH TEST_NOPREFETCH)
                set(TEST_ARGUMENTS -D${TEST_TYPE} -D${TEST_MEMORY} -D${TEST_SIZE} -D${TEST_FETCH})
                add_executable(dot_prod_${EXEC_SUFFIX} dot_prod.c)
                target_compile_options(dot_prod_${EXEC_SUFFIX} PUBLIC ${TEST_ARGUMENTS} -mfpu=neon)
                ...
                
            endforeach()
        endforeach()
    endforeach()
endforeach()
```

## Результаты

Я выделил несколько основных факторов, которые могут повлиять на производительность. Самый важный: наличие интристиков. Этот параметр контролирует переменная ```TEST_TYPE```:

 - [TEST_GENERIC](https://github.com/dernasherbrezon/arm-tests/blob/main/dot_prod.c#L68) - обычный код на С. Это некоторый базовый уровень от которого будут идти все оптимизации.
 - [TEST_NEON4Q](https://github.com/dernasherbrezon/arm-tests/blob/main/dot_prod.c#L85) - загрузка float32 из памяти в регистры сразу по 16 элементов. 
 - [TEST_NEON2Q](https://github.com/dernasherbrezon/arm-tests/blob/main/dot_prod.c#L177) - загрузка float32 из памяти в регистры сразу по 8 элементов. 
 - [TEST_NEON1Q](https://github.com/dernasherbrezon/arm-tests/blob/main/dot_prod.c#L136) - загрузка float32 из памяти в регистры сразу по 4 элемента.

Под каждый тип я написал отдельную реализацию свёртки. Идея такого разделения заключается в том, что данные из памяти могут загружаться долго, и поэтому интересно найти такую комбинацию блоков при которой простой процессора минимален.

Я начал со сравнения двух ARM процессоров между собой: BCM2837B0 и Apple M1.

{{< barchartjs url="/static/img/fir-filter-optimization-simd/types.json" id="typesCompare" title="Алгоритмы" datasource="rpi_dot_prod_nam_nas_npref_optimized_64" datasourceLabel="Raspberrypi" datasource2="m1_dot_prod_nam_nas_npref_optimized_64" datasource2Label="Apple M1" xAxis="type" yAxisLabel="Millis" yAxisUnit="" yAxisLogarithmic="true" staticSrc="/img/fir-filter-optimization-simd/typesCompare.png">}}

Цель такого сравнения была, конечно же, не в том, чтобы убедиться насколько M1 мощный. А скорее увидеть тренд. И он тут есть: оказывается в независимости от реализации процессора, обработка данных по одному 128-битному регистру быстрее, чем по двум и четырём регистрам.

График выше логарифмический для того, чтобы удобно было видеть тренд. Но если приглядеться к цифрам, то видно, что реализация TEST_NEON1Q в среднем в 2 раза быстрее кода на Си с опциями компиляции ``` -O3 -mfloat-abi=hard -march=armv8-a -mfpu=neon```.

Следующим тестом я решил проверить насколько будет влиять выравнивание памяти на результат. Этот параметр контролирует переменная ```TEST_MEMORY```. Для выделения такой памяти я использовал ```posix_memalign```:

```C
#if defined(TEST_ALIGN_MEMORY)
  memory_code = posix_memalign((void **)&output, 32, sizeof(float) * output_len);
  if( memory_code != 0 ) {
    return EXIT_FAILURE;
  }
#else
  output = malloc(sizeof(float) * output_len);
#endif
```

{{< barchartjs url="/static/img/fir-filter-optimization-simd/align_memory.json" id="typesMemory" title="Выравнивание памяти" datasource="rpi_dot_prod_nam_nas_npref_optimized_64" datasourceLabel="Not aligned" datasource2="rpi_dot_prod_am_nas_npref_optimized_64" datasource2Label="Aligned" xAxis="type" yAxisLabel="Millis" yAxisUnit=""  staticSrc="/img/fir-filter-optimization-simd/typesMemory.png">}}

Похоже, выравнивание памяти не влияет на производительность. Либо память изначально выделялась уже выровненной.

Ещё одним важным фактором может быть длина массивов. Допустим, я загружаю из памяти в регистры по 16 float и параллельно считаю свёртку. Но если длина массива не кратна 16-ти, то остаток можно считать загрузкой 8 или 4 float, либо реализовать на Си. В общем же случае входящий массив может быть не кратен ни 16, ни 8, ни 4, тогда придётся по-любому обсчитывать остаток с помощью кода на Си. А что, если расширить исходные массивы до длины кратной 16, 8 или 4? Процессор будет перемножать нули, складывать с нулями и на результат это не повлияет. При этом остаток будет выполняться такими же быстрыми SIMD инструкциями и код в общем случае будет значительно проще. Выглядеть это может вот так:


```C
#if defined(TEST_NEON2Q) && defined(TEST_ALIGN_SIZE)
  if( input_length % 8 != 0 ) {
    final_input_length = ((input_length / 8) + 1) * 8;
  }
  if( taps_length % 8 != 0 ) {
    final_taps_length = ((taps_length / 8) + 1) * 8;
    final_taps = malloc(sizeof(float) * final_taps_length);
    memset(final_taps, 0, sizeof(float) * final_taps_length);
    memcpy(final_taps, taps, sizeof(float) * taps_length);
  }
```

Может не очень элегантно, но выполняется один раз и работает как часы.

{{< barchartjs url="/static/img/fir-filter-optimization-simd/align_size.json" id="typesSize" title="Выравнивание длины массива" datasource="rpi_dot_prod_nam_nas_npref_optimized_64" datasourceLabel="Not aligned" datasource2="rpi_dot_prod_nam_as_npref_optimized_64" datasource2Label="Aligned" xAxis="type" yAxisLabel="Millis" yAxisUnit=""  staticSrc="/img/fir-filter-optimization-simd/typesSize.png">}}

О! Эта оптимизация сработала. На графиках чётко видно ускорение кода для всех функций, написанных с помощью SIMD NEON.

Следующей идеей для оптимизации может быть prefetch данных из памяти. На самом деле это достаточно спекулятивная команда, которая [говорит процессору](https://developer.arm.com/documentation/dui0489/i/CJADCFDC), что скоро будет чтение из заданной области памяти. Я никогда не понимал таких подсказок процессору. Как будто он - человек и такой: "Ну ладно, уговорил. Будет быстрее". Но почему бы и не попробовать? Тут, правда, не очень понятно в какой момент вызывать эту функцию. Я сделал сразу же после загрузки из памяти:

```C
        a_val = vld2q_f32(aPtr);
        b_val = vld2q_f32(bPtr);
#if defined(TEST_PREFETCH)
        __builtin_prefetch(aPtr+8);
        __builtin_prefetch(bPtr+8);
#endif
```

{{< barchartjs url="/static/img/fir-filter-optimization-simd/prefetch.json" id="testPrefetch" title="PREFETCH" datasource="rpi_dot_prod_nam_nas_npref_optimized_64" datasourceLabel="No prefetch" datasource2="rpi_dot_prod_nam_nas_pref_optimized_64" datasource2Label="With prefetch" xAxis="type" yAxisLabel="Millis" yAxisUnit=""  staticSrc="/img/fir-filter-optimization-simd/testPrefetch.png">}}

Ну такое. Разница видна, но в рамках погрешности.

Кстати, на M1 эта оптимизация сделала всё только хуже:

{{< barchartjs url="/static/img/fir-filter-optimization-simd/prefetch.json" id="testPrefetchM1" title="PREFETCH M1" datasource="m1_dot_prod_nam_nas_npref_optimized_64" datasourceLabel="No prefetch" datasource2="m1_dot_prod_nam_nas_pref_optimized_64" datasource2Label="With prefetch" xAxis="type" yAxisLabel="Millis" yAxisUnit=""  staticSrc="/img/fir-filter-optimization-simd/testPrefetchM1.png">}}

Помимо всех этих оптимизаций я пытался собирать бинарники с разными опциями компиляции:

 - без флагов оптимизации компиляции. Только ```-mfpu=neon```
 - оптимизация под 64-битные процессоры: ```-O3 -mfloat-abi=hard -march=armv8-a -mfpu=neon```
 - оптимизации под 32-битные процессоры: ```-O3 -mfloat-abi=hard -march=armv7-a -mfpu=neon```

{{< barchartjs url="/static/img/fir-filter-optimization-simd/compile.json" id="testCompile" title="Флаги компиляции" datasource="rpi_dot_prod_generic_nam_nas_npref" datasourceLabel="TEST_GENERIC" datasource2="rpi_dot_prod_neon2q_nam_nas_npref" datasource2Label="TEST_NEON2Q" xAxis="type" yAxisLabel="Millis" yAxisUnit=""  staticSrc="/img/fir-filter-optimization-simd/testCompile.png">}}

Из графика видно, что компилятор действительно делает что-то полезное и дополнительные флаги ускоряют работу программы. Но при этом реализация алгоритма с помощью интристиков всё равно быстрее.

А ещё видно, что 32-битные и 64-битные инструкции выполняются одинаковое количество времени. Я бы ожидал, что шина 64-битного процессора в 2 раза больше и может загружать в 2 раза быстрее данные из памяти, но такого не происходит.

## Выводы

Я ещё немного поиграюсь с разными настройками, но уже ясно, что [arm-tests](https://github.com/dernasherbrezon/arm-tests) очень удобен для быстрой проверки гипотез. Можно добавить другие алгоритмы и посравнивать.

Кстати, в pull request есть ошибка: [используется один и тут же аккумулятор](https://github.com/airspy/airspyone_host/pull/89/files#diff-e67cb16e76125bf3df6e65eb49cd9795deb99fceef4a073d680b013946065a79R185) для обработки двух независимых [FMA операций]({{< ref "/fma-raspberrypi" >}}). Если использовать два аккумулятора и потом их дополнительно сложить вне цикла, то скорость ожидаемо возрастёт в 2 раза.
