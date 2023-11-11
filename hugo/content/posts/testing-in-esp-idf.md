---
title: "Тестирование в ESP-IDF"
date: 2023-11-10T21:58:18+01:00
draft: false
tags:
  - lora-at
  - esp-idf
  - тестирование
---

Неотъемлемой частью любого современного проекта является тестирование. Мой [старый-новый проект lora-at]({{< ref "/posts/lora-at" >}}) - не исключение. После того, как я смигрировал его с PlatformIO на ESP-IDF, мне пришлось переписать все тесты.

[Изначально](https://github.com/dernasherbrezon/lora-at/blob/7cba855415422f44db5b2759d54e6f59af0f0639/test/test_at/test_AtHandler.cpp) тесты мокировали работу с чипом sx127x, компилировались под Linux/MacOS и проверяли вход-выход at_handler. В текущий версии такой подход не сработает:

 - Во-первых, at_handler стал зависить от множества других компонент. Появилась поддержка экрана, режима глубокого сна и тд. Старые тесты это не учитывали.
 - Во-вторых, появились зависимости на внутренние компоненты ESP-IDF, которые пока не компилируются под Linux/MacOS. То же логирование [работать не будет](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/host-apps.html).
 - В-третьих, много логики появилось именно в компонентах, связанных с железом. Их бы тоже неплохо было бы протестировать.
 
Пришлось открывать [документацию ESP-IDF](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/unit-tests.html) и вдумчиво исследовать возможности.

## Юнит тестирование

ESP-IDF позволяет писать юнит тесты с помощью библиотеки unity. Достаточно создать папку test и подключить её в CMakeLists.txt:

```cmake
idf_component_register(SRC_DIRS "."
                       INCLUDE_DIRS "."
                       REQUIRES unity)
```

На самом деле нет. В официальной документации опущено, как мне кажется, достаточно важное НО: полученные юнит тесты нужно подключать к приложению unit-test-app, которое находится в ```esp-idf/tools/unit-test-app```. И вообще, это приложение, скорее всего, используется для тестирования самого фреймворка. При должном старании можно запустить собственные тесты из этого приложения, но выглядит это достаточно неудобно. Опять же подцепятся все тесты фреймворка, будут долго компилироваться - совсем не то, что хочется.

Вместо этого можно самому написать приложение. По сути unit-test-app - это обычное приложение под ESP32, которое имеет ```void app_main(void)```:

```c
#include <unity.h>

void app_main(void) {
  unity_run_menu();
}
```

Обязательная конфигурация в sdkconfig. Без неё прошивка будет постоянно падать.

```
CONFIG_ESP_TASK_WDT=n
```

Тесты регистрируются в глобальном списке и доступны для выполнения. Функция ```unity_run_menu``` на самом деле не запускает тесты, а запускает меню, в котором, подключившись по UART интерфейсу, можно выбрать нужный тест и запустить. Результат запуска всё равно передаётся назад по UART, так что совсем не важно как запускаются тесты. А вот возможность запустить вручную каждый тест - это удобно.

![](/img/testing-in-esp-idf/1.png)

Ещё стоит сказать, что ESP-IDF значительно расширяет [unity](https://github.com/ThrowTheSwitch/Unity/blob/master/docs/UnityGettingStartedGuide.md), позволяя писать вот такие конструкции:

```c
TEST_CASE("success", "[at_timer]") {
  // test case
}
```

Вместо стандартного:

```c
void test_function_should_doBlahAndBlah(void) {
    //test stuff
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_function_should_doBlahAndBlah);
    return UNITY_END();
}
```

Из недостатков unity - нельзя для каждого теста определять ```void setUp()``` и ```void tearDown()```. Каждый тест в ESP-IDF находится в своём компоненте и, в принципе, они друг от друга не зависят. Однако, из-за того, что в итоге они линкуются в один проект unit-test-app, названия функций нельзя дублировать.

## Valgrind у себя дома

В Linux есть такая замечательная программа, как [Valgrind](https://valgrind.org). С её помощью можно искать утечки памяти. Однако, Valgrind не поддерживает микроконтроллеры, и непонятно что делать в таком случае. На помощь приходит внутренний инструментарий ESP-IDF - [Heap Memory Debugging](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/heap_debug.html). Идея заключается в следующем:

 - для каждого тест кейса в методе ```setUp``` включать анализ потребления памяти ```heap_trace_start(HEAP_TRACE_LEAKS)```.
 - а при завершении теста в методе ```void tearDown()``` выключать и считать разницу выделенных объектов:
 
```c
void tearDown() {
  ESP_ERROR_CHECK(heap_trace_stop());
  heap_trace_dump();
  TEST_ASSERT_MESSAGE(heap_trace_get_count() == 0, "memory leak");
}
```

Дополнительно необходимо включить поддержку Heap Memory Debugging в sdkconfig:

```
CONFIG_HEAP_POISONING_DISABLED=y
CONFIG_HEAP_TRACING_STANDALONE=y
CONFIG_HEAP_TRACING=y
CONFIG_HEAP_TRACING_STACK_DEPTH=2
```

Первые несколько простеньких тестов сработали отлично. Но вот когда пришла очередь более сложных, появились утечки памяти:

```
Running success...
I (158592) lora-at: inactivity timer started: 0.03s
I (158622) lora-at: inactivity timer stopped
1 allocations trace (100 entry buffer)
12 bytes (@ 0x3ffb5800) allocated CPU 0 ccount 0xe877f00c caller 0x400d3588:0x400d395c
0x400d3588: get_desc_for_int at /mnt/disk/esp/esp-idf/components/esp_hw_support/intr_alloc.c:147

0x400d395c: esp_intr_alloc_intrstatus at /mnt/disk/esp/esp-idf/components/esp_hw_support/intr_alloc.c:552

12 bytes 'leaked' in trace (1 allocations)
total allocations 6 total frees 7
/mnt/disk/tmp/tmp.IgQEOLXRBb/components/at_timer/test/test_at_timer.c:18:success:FAIL:Function [at_timer].  memory leak
Test ran in 69ms
```

Утечки памяти происходят внутри самого ESP-IDF! Благо он опенсорс и можно разобраться почему:

```
//Theoretically, we could free the vector_desc... not sure if that's worth the few bytes of memory
//we save.(We can also not use the same exit path for empty shared ints anymore if we delete
//the desc.) For now, just mark it as free.
```

Да, мистер Jeroen Domburg, несколько байтов на самом деле - это 12 байт. Если так подумать, то он прав, внутренние структуры инициализируются только один раз для каждого прерывания, а потом переиспользуются. Если по-честному удалять выделенную память, то может так получиться, что прерывание создаётся в цикле и сразу освобождается. Постоянная инициализация и освобождение памяти будут вести к фрагментации. А это плохо. С другой стороны можно было сразу выделать сколько нужно памяти на внутренние структуры, но тогда будет использоваться памяти больше, чем нужно. А это тоже плохо. Но решать-то вопрос как-то нужно! А вдруг память течёт в моём коде? Или будет течь? Я не придумал ничего более лучшего, чем прогрев внутреннего состояния драйвера перед стартом программы:

```c
void app_main(void) {
  i2c_driver_install(I2C_NUM_1, I2C_MODE_MASTER, 0, 0, 0);
  i2c_driver_delete(I2C_NUM_1);
}
```

В таком же ключе пришлось прогревать логи, nvs и структуры для работы с таймерами. Зато в результате я могу отлавливать утечки памяти в своём коде.

## Интеграционные тесты

Интеграционные тесты очень похожи на те, которые я писал для тестирования [библиотеки sx127x]({{< ref "/testing-sx127x" >}}). Напомню, что основная идея была в том, чтобы с помощью питона и библиотеки pytest-embedded посылать команды в приёмник и передатчик, получать результат работы и сравнивать с ожидаемым. Для lora-at даже не пришлось писать отдельного приложения для обработки команд - оно само по себе приложение для обработки AT команд! Вот что в результате получилось:

```python
@pytest.mark.generic
@pytest.mark.parametrize('count', [
    2,
], indirect=True)
def test_common_at_commands(dut: Tuple[Dut, Dut]) -> None:
    dut_tx = dut[0]
    dut_rx = dut[1]
    
    dut_rx.write('AT+LORARX=436703003,250000,10,5,18,10,8,4,1,1,1,0')
    dut_rx.expect('OK', timeout=3)
    dut_tx.write('AT+LORATX=CAFE,436703003,250000,10,5,18,10,8,4,1,1,1,0')
    dut_tx.expect('OK', timeout=3)
    dut_rx.expect('received frame', timeout=3)    
```

Сначала RX устройство начинает слушать эфир, потом TX устройство передаёт в эфир пакет, а затем ожидается, что RX устройство приняло пакет. В таком ключе я написал несколько десятков тест кейсов. Единственное, с чем не разобрался - это таймаут. Несмотря на то, что я следую документации и явно указываю таймауты ожидания ответа, pytest почему-то ждёт несколько минут прежде, чем упасть. Хотя при этом он пишет, что упал по указанному мною таймауту. Магия питона не иначе.

## Результаты

В результате получился вполне тестируемый код. Вся инфраструктура для тестов настроена и работает. Большинство функциональности оттестировано. Время переходить к самому вкусному - тестирование потребления энергии с помощью [Power Profiler Kit II](https://www.nordicsemi.com/Products/Development-hardware/Power-Profiler-Kit-2).
