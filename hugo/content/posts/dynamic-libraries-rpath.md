---
title: "Динамические библиотеки, RPATH и Conan"
date: 2021-02-18T23:11:18+00:00
draft: false
tags:
  - c
---
Эта статья - скорее конспект того, что я узнал за последнюю неделю о динамических библиотеках, RPATH и Conan.

## Введение

Никто в здравом уме не начнёт изучать то, как линкуются библиотеки в MacOS. Поэтому для начала я попытаюсь обрисовать проблему, которую пытался решить.

Итак, на заре времён, когда жёсткие диски компьютеров были маленькие, память компьютеров была маленькая, люди придумали переиспользование библиотек. Как всё это работает? Допустим у нас есть 2 приложения:

 - калькулятор, зависящий от библиотек:
   - math
   - ncurses
 - планировщик задач, зависящий от библиотек:
   - pthread
   - ncurses

При запуске, этих двух приложений, операционная система будет загружать необходимые библиотеки в память. Но так, как библиотека ncurses уже один раз будет загружена, то операционная система не будет загружать её второй раз. Вместо этого приложение "планировщик задач" получит ссылку на память уже загруженной библиотеки. Это достаточно безопасно, потому что библиотека не может поменяться (я намеренно упрощаю ситуацию с глобальными переменными и thread-safe гарантиями). В итоге логически мы загрузили две библиотеки, а физически только одну (Resident memory vs Shared memory). Чем больше приложений будет использовать одни и те же библиотеки, тем быстрее будет старт приложений и меньше потребление памяти.

Помимо экономии памяти, такое переиспользование улучшало поддерживаемость операционной системы. Допустим, в одной из библиотек (ncurses) обнаружена уязвимость. Для того чтобы её исправить, достаточно обновить библиотеку в одном месте. Все приложения, которые используют эту библиотеку автоматически получат обновление безопасности. Это особенно важно, если некоторые приложения (например, "планировщик задач") редко обновляются или вообще заброшены своими создателями.

Альтернативой этому подходу являются толстые дистрибутивы. Я уже писал о плюсах [толстых и тонких дистрибутивов]({{< ref "/thin-and-fat-distributives" >}}) для Java. В целом для C/C++ аргументы значительно совпадают. Однако, исторически, приложения операционных систем являются тонкими дистрибутивами. [Многие ОС](https://fedoraproject.org/wiki/Bundled_Libraries?rd=Packaging:Bundled_Libraries) до сих пор [требуют поставлять приложения](https://www.debian.org/doc/debian-policy/ch-source.html#s-embeddedfiles) в виде тонких дистрибутивов.

Большинство аргументов за и против тонких дистрибутивов имели смысл лет 20 назад. Сейчас же, когда размер памяти и диска не так важны, появляются новые аргументы против:

 - количество библиотек и приложений стало настолько много, что мейнтейнеры популярных систем уже не в состоянии поставлять пакеты с последними версиями библиотек. Зачастую они фиксируют стабильную версию и выпускают небольшие обновления безопасности.
 - опять же, из-за количества библиотек и зависимостей между ними, стало сложнее найти тот список версий, который подходил бы большинству приложений. Если калькулятор будет использовать ncurses версии 1.0, а "планировщик задач" ncurses версии 2.0, то непонятно какую версию ncurses нужно ставить. apt, rpm, yum позволяют ставить только одну версию библиотеки. Нельзя поставить одновременно версию 1.0 и 2.0. Если эти версии не совместимы между собой, то придётся выбирать какое приложение включить в состав операционной системы.
 - нужно постоянно обновлять версию всей операционной системы. Ведь новые версии библиотек уже не появятся. А писать код, половина которого обвешана ```#if NCURSES = 1.0 ... #else if NCURSES = 2.0 ... #endif``` никому не хочется.

Всё это пронеслось у меня в голове за считанные секунды, когда я думал о том, как исправить "[Compiling issue - rtlsdr_set_bias_tee](https://github.com/dernasherbrezon/sdr-server/issues/3)" в sdr-server.

## [Conan](https://conan.io)

Взвесив все за и против, я решил пойти путём толстых дистрибутивов. Для этого я решил разобраться в модной технологии, которая у всех на слуху - [Conan](https://conan.io) от компании jfrog.

![conan-install_flow](/img/dynamic-libraries-rpath/conan-install_flow.png)

Основная идея проекта заключается в том, что собранные библиотеки уже лежат на центральном сервере. И для того, чтобы их использовать, достаточно подключить в проект. А Conan сам их скачает и правильно подставит пути. Делается это с помощью небольшого конфига:

```
[requires]
rtlsdr/0.6.4
volk/2.4.1

[build_requires]
check/0.15.2@r2cloud/stable

[generators]
cmake
```

После этого подключить в CMakeLists.txt Conan:

```
include(${CMAKE_BINARY_DIR}/conanbuildinfo.cmake)
conan_basic_setup()
```

А потом в папке ```build``` вызвать команду ```install```:

```
#: conan install ..
```

Эта команда скачает зависимости, положит их в локальный репозиторий и сгенерирует cmake конфиг в котором прописаны все зависимые библиотеки. После этого остаётся только подключить эти библиотеки к исполняемому файлу:

```
target_link_libraries(sdr_server ${CONAN_LIBS})
```

И собрать проект:

```
cmake ..
```

Это было всё в теории. На практике всё совсем по-другому.

## Практика

На практике библиотек в [conan-center](https://conan.io/center/) очень мало. Да и те, что есть почему-то [неправильно собраны](https://github.com/conan-io/conan-center-index/pull/4582). Я, в общем-то, был готов к этому, поэтому собрался с мыслями и начал разбираться во всех тонкостях линковки библиотек, их дистрибуции и то, как это реализовано в Conan.

Итак, для того, чтобы понять как правильно собрать библиотеку, необходимо разобраться как она линкуется с программой. Для этого нужно сделать пару шагов назад.

В cmake есть два совершенно разных понятия: build и install. Я даже картинку нарисовал, чтобы ешё раз закрепить это важное знание:

![cmake build vs install](/img/dynamic-libraries-rpath/build-install.png)

Во время фазы "build" приложение компилируется и из него собираются артефакты. Во время фазы "install" эти артефакты копируются в правильное место внутри операционной системы. Тут есть очень важная вещь: разделение на две фазы достаточно условное. Это не maven, где есть чёткие правила когда и что должно выполняться. В большинстве случаев, папка build после сборки представляет собой помойку разных файлов разбросанных по папкам. И некоторые библиотеки [приводят в порядок](https://github.com/gnuradio/volk/blob/master/CMakeLists.txt#L283) публичные header файлы и библиотеки только во время фазы "install". Несмотря на такой беспорядок во время фазы "build", любой разработчик ожидает, что приложение можно запустить. Это очень важный момент, который нужно понимать, чтобы разобраться в правильном подключении динамических библиотек.

Далее я постараюсь описать, как Conan встраивает зависимости в разные фазы.

### Компиляция

Самый простой шаг. Conan использует пути из локального кэша и передаёт их компилятору:

```
[ 37%] Building C object CMakeFiles/perf_xlating.dir/test/perf_xlating.c.o
/Library/Developer/CommandLineTools/usr/bin/cc \
 -I/Users/dernasherbrezon/.conan/data/check/0.15.2/r2cloud/stable/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/include \
 -I/Users/dernasherbrezon/.conan/data/rtlsdr/0.6.4/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/include \
 -I/Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/include \
 -I/usr/local/include -std=c99 -O3 -DNDEBUG  -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX11.0.sdk -std=gnu99 -o CMakeFiles/perf_xlating.dir/test/perf_xlating.c.o -c /Users/dernasherbrezon/git/sdr-server/test/perf_xlating.c
```

В данном случае кэш находится в ```/Users/dernasherbrezon/.conan/data/``` и используются библиотеки ```rtlsdr, volk & check```.

### Линковка

Здесь аналогично: пути из локального кэша используются при линковке.

```
[ 40%] Linking C executable bin/perf_xlating
/usr/local/Cellar/cmake/3.19.4/bin/cmake -E cmake_link_script CMakeFiles/perf_xlating.dir/link.txt --verbose=1
/Library/Developer/CommandLineTools/usr/bin/cc -std=c99 -O3 -DNDEBUG  -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX11.0.sdk -Wl,-search_paths_first -Wl,-headerpad_max_install_names CMakeFiles/perf_xlating.dir/test/perf_xlating.c.o -o bin/perf_xlating  \
 -L/Users/dernasherbrezon/.conan/data/check/0.15.2/r2cloud/stable/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib \
 -L/Users/dernasherbrezon/.conan/data/rtlsdr/0.6.4/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib \
 -L/Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib \
 lib/libsdr_serverLib.a \
 -lcheck -lrtlsdr -lvolk /Library/Developer/CommandLineTools/SDKs/MacOSX11.0.sdk/usr/lib/libz.tbd /usr/local/lib/libconfig.dylib -lpthread -lm 
```

### Запуск после build

Приложение запустится без проблем, но здесь ожидает сюрприз: абсолютные пути к зависимым библиотекам. При линковке пути до библиотек прописываются в исполняемый файл.

```
otool -l bin/perf_xlating|grep -B 2 volk
          cmd LC_LOAD_DYLIB
      cmdsize 152
         name /Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib/libvolk.2.4.dylib (offset 24)
```

Такие программы просто не будут работать на другом компьютере из-за абсолютных путей. 

### Запуск после install

Приложение просто не запустится. Для того чтобы оно запустилось, нужно положить все зависимые библиотеки рядом с бинарником. В Conan это делается просто. Достаточно дописать в файл conanfile.txt следующее:

```
[imports]
bin, *.dll -> ./bin 
lib, *.dylib* -> ./lib
lib, *.so* -> ./lib
```

Эта секция будет выполняться во время команды ```conan import ..``` и скопирует все библиотеки из локального кэша в директорию приложения. Например, ```/Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib/libvolk.2.4.dylib``` -> ```sdr-server/build/lib/libvolk.2.4.dylib```.

Следующим шагом необходимо поменять абсолютные пути на относительные внутри исполняемого файла. И вот тут как раз появляется такая вещь как RPATH. Это специальная секция в исполняемом файле, которая содержит директории, в которой нужно искать динамические библиотеки. В эту секцию можно положить значение со специальной переменной @executable_path, чтобы линковщик начал искать библиотеки относительно исполняемого файла. В итоге алгоритм будет такой:

 1. Загрузить исполняемый файл
 2. Для каждого имени библиотеки, взять его путь. Если он содержит ключевое слово @rpath, то
 3. Найти секцию RPATH в исполняемом файле. Если она есть, то
 4. Проверить значение секции, если оно содержит @executable_path, то подставить текущий путь до бинарника
 5. В полученном пути поискать библиотеку.

В MacOS, правда, всё чуть запутаннее. Библиотека содержит внутри себя путь, где она находится:

```
otool -l /Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib/libvolk.2.4.dylib|grep -A 2 LC_ID_DYLIB
          cmd LC_ID_DYLIB
      cmdsize 152
         name /Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib/libvolk.2.4.dylib (offset 24)
```

Это выглядит очень странно. Видимо, при линковке этот путь копируется из библиотеки в исполняемый файл. Понятное дело, в таких библиотеках тоже нужно заменить абсолютные пути на относительные. Это можно сделать специальной программой:

```
install_name_tool -id @rpath/libvolk.2.4.dylib /Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib/libvolk.2.4.dylib
```

Теперь путь содержит специальную метку @rpath:

```
otool -l /Users/dernasherbrezon/.conan/data/volk/2.4.1/_/_/package/6a83d7f783e7ee89a83cf2fe72b5f5f67538e2a6/lib/libvolk.2.4.dylib|grep -A 2 LC_ID_DYLIB
          cmd LC_ID_DYLIB
      cmdsize 56
         name @rpath/libvolk.2.4.dylib (offset 24)
```

Эта метка будет подставляться из RPATH исполняемого файла. Теперь зависимости выглядят следующим образом:

```
otool -L bin/perf_xlating 
bin/perf_xlating:
	@rpath/libcheck.0.dylib (compatibility version 0.0.0, current version 0.15.2)
	@rpath/librtlsdr.0.dylib (compatibility version 0.0.0, current version 0.6.4)
	@rpath/libvolk.2.4.dylib (compatibility version 2.4.0, current version 0.0.0)
```

Последним шагом нужно задать секцию RPATH, чтобы начать использовать относительные пути к библиотекам.

```
install_name_tool -add_rpath @executable_path/../lib bin/perf_xlating
```

После всех этих манипуляций можно проверить результат. Так как поиск библиотек происходит в рантайме, то для того, чтобы узнать получившиеся пути, нужно запустить программу:

```
DYLD_PRINT_LIBRARIES=YES bin/perf_xlating 
dyld: loaded: <7AB49406-C965-3CD7-99E5-398BC69A6567> /<edited>/sdr-server/build/bin/perf_xlating
dyld: loaded: <26F34288-9251-3468-9ED9-10A595F04DED> /<edited>/sdr-server/build/bin/../lib/libcheck.0.dylib
dyld: loaded: <C8BA4B0A-EE3A-3322-9B14-1C68CFCF977B> /<edited>/sdr-server/build/bin/../lib/librtlsdr.0.dylib
dyld: loaded: <24DC8413-C299-3CD5-ADDD-5785C39B6084> /<edited>/sdr-server/build/bin/../lib/libvolk.2.4.dylib
...
```

Идеально.

Для Linux шаги примерно такие же, только проще. Не нужно прописывать пути внутри самих библиотек.

Пара слов о cmake. Программу ```install_name_tool``` можно заменить командами cmake. К сожалению, в cmake существует десяток различных параметров, которые неявно влияют на результат.

```
CMAKE_INSTALL_RPATH
CMAKE_BUILD_WITH_INSTALL_RPATH
CMAKE_INSTALL_RPATH_USE_LINK_PATH
CMAKE_BUILD_RPATH
CMAKE_SKIP_BUILD_RPATH
INSTALL_RPATH
BUILD_RPATH
```

У меня не получилось заставить cmake проставлять корректный RPATH в исполняемый файл. Возможно, Conan [неявно перезаписывает](https://docs.conan.io/en/latest/howtos/manage_shared_libraries/rpaths.html) определённые переменные, тем самым ломая алгоритм.

## Заключение

Потратив неделю на изучение, создание pull request в Conan, volk и libcheck, я в итоге решил сделать всё по-старинке. Идея толстых дистрибутивов хороша, но инфраструктура пока не готова к этому. Будет ли когда-нибудь готова инфраструктура для С/С++ проектов с её cmake, make, pkgconf, autotools, conan - большой вопрос.   