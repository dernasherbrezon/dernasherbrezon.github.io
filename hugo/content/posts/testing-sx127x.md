---
title: "Тестирование sx127x"
date: 2023-04-23T18:15:18+01:00
draft: false
tags:
  - sx127x
  - esp32
  - embedded
  - c
  - тестирование
---
Я продолжаю разрабатывать библиотеку для работы с чипом [sx127x](https://github.com/dernasherbrezon/sx127x) и в этом посте речь пойдёт о тестировании. Но для начала небольшая предыстория. Изначально библиотека поддерживала только LoRa модуляцию и была достаточно небольшой. По сути это была небольшая обёртка над регистрами sx127x, которая позволяла из Си вызывать нужные функции. Основная ценность скорее была в том, чтобы перевести магические числа и SPI протокол в понятные слова из даташита. После того, как я решил добавить поддержку FSK модуляции, библиотека разрослась. Нужно было поддержить потоковую обработку входящих сообщений, реагировать на гораздо большее количество прерываний и при этом не сломать старый функционал. В этот момент стало понятно, что нужны тесты.

## Юнит тесты

Из-за того, что библиотека не зависит от конкретных плат и операционных систем, писать юнит тесты оказалось просто. Достаточно сделать mock-реализацию SPI интерфейса и возвращать ожидаемые данные. Например, регистры sx127x можно эмулировать следующим образом:

```c
void spi_mock_registers(uint8_t *expected, int code) {
  sx127x_mock_registers = expected;
  sx127x_mock_expected_code = code;
}
```

А в реализации использовать их вот так:

```c
#include <sx127x_spi.h>

int sx127x_spi_read_registers(int reg, void *spi_device, size_t data_length, uint32_t *result) {
  for (int i = 0; i < data_length; i++) {
    *result = ((*result) << 8);
    *result = (*result) + sx127x_mock_registers[reg + i];
  }
}
```

Единственное, что нужно учитывать - это специальный регистр 0x00 (FIFO), чтение и запись в который должна работать по-другому. Полную реализацию [mock SPI](https://github.com/dernasherbrezon/sx127x/blob/main/test/sx127x_mock_spi.c) можно посмотреть в репозитории.

Для юнит тестов я использовал библиотеку [libcheck](https://libcheck.github.io/check/), потому что другие мои проекты [sdr-server](https://github.com/dernasherbrezon/sdr-server) и [sdr-modem](https://github.com/dernasherbrezon/sdr-modem) тоже её используют. Как и любая другая библиотека эта позволяет инициализировать состояние перед каждым тестом:

```c
void setup() {
  registers = (uint8_t *)malloc(registers_length * sizeof(uint8_t));
  memset(registers, 0, registers_length);
  registers[0x42] = 0x12;
  spi_mock_registers(registers, SX127X_OK);
  ck_assert_int_eq(SX127X_OK, sx127x_create(NULL, &device));
  spi_mock_write(SX127X_OK);
}
```

Вызывает тест. Например, тест обработчика CAD прерывания выглядит так:

```c
START_TEST(test_lora_cad) {
  ck_assert_int_eq(SX127X_OK, sx127x_set_opmod(SX127x_MODE_CAD, SX127x_MODULATION_LORA, device));
  ck_assert_int_eq(registers[0x40], 0b10000000);
  sx127x_lora_cad_set_callback(cad_callback, device);
  registers[0x12] = 0b00000101;  // cad detected
  sx127x_handle_interrupt(device);
  ck_assert_int_eq(1, cad_status);

  registers[0x12] = 0b00000100;  // cad not detected
  sx127x_handle_interrupt(device);
  ck_assert_int_eq(0, cad_status);
}
END_TEST
```

И очищать состояние после каждого теста с помощью фукнции ```teardown()```:

```c
void teardown() {
  if (device != NULL) {
    sx127x_destroy(device);
    device = NULL;
  }
  if (registers != NULL) {
    free(registers);
    registers = NULL;
  }
}
```

В итоге мне удалось написать порядочное количество тестов и добиться [74.7% покрытия тестами](https://sonarcloud.io/component_measures?id=dernasherbrezon_sx127x&metric=coverage&view=list).

![](/img/testing-sx127x/1.png)

Вообще, несмотря на кажущуюся простоту решения, мне удалось найти несколько довольно досадных ошибок! В основном связанных с тем, что я где-то неправильно сдвигал биты или выставлял не те регистры. Так что время потраченное на написание юнит тестов и их настройку полностью себя оправдало.

## Интеграционные тесты

Юнит тесты всем хороши. Но как понять, что выставленные биты в правильном регистре действительно позволяют отправлять и получать сообщения? На помощь приходят интеграционные тесты. Если бы меня спросили: "А как написать интеграционные тесты для Java проекта?", то я бы без запинки ответил, что-нибудь про докер, среду тестирования или [mock HTTP сервер]({{< ref "/mock-server" >}}). Когда же встал вопрос о том, как протестировать железо, то мне потребовалось несколько недель, чтобы разобраться с проблемой.

Так как у меня есть платы TTGO, то я решил взять ESP-IDF в котором есть поддержка [юнит](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/unit-tests.html) и [интеграционных](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/contribute/esp-idf-tests-with-pytest.html) тестов. Они скорее ориентированы на тестирования фреймворка, но для сторонних приложений тоже подходят.

Все мои интеграционные тесты должны быть построены примерно по одному шаблону:

 1. Первое устройство должно начать слушать эфир
 2. Второе устройство должно послать сообщение
 3. Первое устройство должно успешно получить сообщение
 4. Тест должен проверить, что сообщение получено и оно верное
 
ESP-IDF фреймворк предлагает реализовывать такие тесты следующим образом:

 1. Создать отдельное приложение на Си с тестовыми сценариями
 2. Использовать [pytest](https://docs.pytest.org/en/7.3.x/) + [pytest-embedded](https://docs.espressif.com/projects/pytest-embedded/en/latest/) для того, чтобы запускать сценарии в нужной последовательности
 
### Тестовые сценарии

Тестовые сценарии должны лежать в обычном приложении для ESP32. Оно должно иметь точку входа ```app_main()```, конфигурацию CMake, зависимости и пр. Основной его задачей будет запуск меню библиотеки unity:

![](/img/testing-sx127x/2.png)

[unity](https://github.com/ThrowTheSwitch/Unity) - это ещё одна библиотека юнит тестов для Си. Она позволяет запускать их в интерактивном режиме. Если подключиться к устройству по serial интерфейсу, то можно напечатать название теста, нажать "Enter" и библиотека запустит этот тест. Основная функция выглядит достаточно просто:

```c
#include <unity_test_runner.h>

#include "test_lora.c"

void app_main(void) {
  unity_run_menu();
}
```

Я решил вынести тесты в отдельные файлы для удобства. На самом деле ничего не мешает их реализовывать сразу в ```main.c```. Так как ```unity_run_menu``` ожидает ввод в бесконечном цикле, то необходимо выключить [TWDT](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/wdts.html). Это специальная мера предосторожности, которая перезапускает приложение, если какой-то таск уходит в бесконечный цикл. Выключается в файле ```sdkconfig.defaults```:

```
CONFIG_ESP_TASK_WDT=n
```

Тесты для отправки сообщения и проверки выглядят следующим образом:

```c
TEST_CASE("sx127x_test_lora_rx_explicit_header", "[lora]") {
  sx127x_rx_set_callback(rx_callback, fixture->device);
  sx127x_set_opmod(SX127x_MODE_RX_CONT, SX127x_MODULATION_LORA, fixture->device);
  xSemaphoreTake(fixture->rx_done, portMAX_DELAY);
  uint8_t expected[] = {0xCA, 0xFE};
  TEST_ASSERT_EQUAL_UINT16(sizeof(expected), fixture->rx_data_length);
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, fixture->rx_data, sizeof(expected));
}

TEST_CASE("sx127x_test_lora_tx_explicit_header", "[lora]") {
  // some initialization
  sx127x_lora_tx_set_for_transmission(data, sizeof(data), fixture->device);
  sx127x_set_opmod(SX127x_MODE_TX, SX127x_MODULATION_LORA, fixture->device);
  ESP_LOGI("sx127x_test", "done. waiting for message");
  xSemaphoreTake(fixture->tx_done, portMAX_DELAY);
}
```

Это скорее даже не тесты, а небольшие куски кода, которые нужно запускать на разных устройствах в определённой последовательности. После компиляции прошивку с одинаковыми тестами нужно загрузить на два разных устройства. На первом устройстве запустить тест ```sx127x_test_lora_rx_explicit_header```, а на втором ```sx127x_test_lora_tx_explicit_header```. Как только сообщение отправится, ```tx``` тест сразу же завершится. А ```rx``` дождётся получения сообщения и проверит результат. Выглядит достаточно просто, хотя у меня заняло несколько дней в этом разобраться. Меня в первую очередь смутила официальная документация, которая говорит, что нужно использовать макрос ```TEST_CASE_MULTIPLE_DEVICES```. Хотя на самом деле этого ничего не нужно, потому что устройства между собой никак не синхронизированы. И синхронизацию нужно по-любому делать через serial интерфейс вручную. Или с помощью python скрипта.

### pytest

Алгоритм для запуска таких интеграционных тестов может быть автоматизирован с помощью скрипта на python. В моём случае это выглядит как то так:

```python
@pytest.mark.supported_targets
@pytest.mark.generic
@pytest.mark.parametrize('count', [
    2,
], indirect=True)
def test_single(dut: Tuple[Dut, Dut]) -> None:
    dut_rx = dut[0]
    dut_tx = dut[1]

    dut_rx.expect('Press ENTER to see the list of tests')
    dut_rx.write('"sx127x_test_lora_rx_explicit_header"')

    dut_tx.expect('Press ENTER to see the list of tests')
    dut_tx.write('"sx127x_test_lora_tx_explicit_header"')
    dut_tx.expect_unity_test_output()

    dut_rx.expect_unity_test_output()
```

Запускается этот скрипт с помощью команды pytest:

```bash
pytest --target esp32 --port="/dev/ttyACM0|/dev/ttyUSB0"
```

Эта команда выполнит следующие шаги:

 1. Загрузит прошивку на два устройства ```/dev/ttyACM0``` и ```/dev/ttyUSB0```
 2. Запустит скрипт
 3. Скрипт подключится по serial интерфейсу к обоим устройствам
 4. Запустит тест ```sx127x_test_lora_rx_explicit_header```
 5. Потом тест ```sx127x_test_lora_tx_explicit_header```
 6. Дождётся выполнения тестов на обоих устройствах

![](/img/testing-sx127x/3.png)

## Послесловие

Тестировать железо можно, но для этого нужно иметь много утилит и инструментов. ESP-IDF из коробки предоставляет хороший набор, который позволяет писать сложные тесты. Посмотрим, хватит ли его функционала для моих нужд. У меня в планах добавить тесты для LoRa, FSK, OOK, различные режимы отправки сообщений с контрольной суммой и без, а так же проверить потребление памяти.