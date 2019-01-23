---
title: "Рефакторинг старых систем"
date: 2009-05-11T13:14:18+01:00
draft: false
tags:
  - идеи
  - java
  - refactoring
  
---
Навеяно http://www.amazon.com/Working-Effectively-Legacy-Robert-Martin/dp/0131177052

Мне достаточно часто приходилось работать с наследными системами. Поэтому выработал некоторые свои собственные интересные практики при работе с такими системами.

  1. Зачастую имена классов, методов и переменных не отражают сути. В таких случаях обычно переименовывают их. Однако в наследных системах такого делать не рекомендуется. Даже при использовании мощных инструментов в современных IDE. Это связано с тем что в конечном итоге подобные системы собираются своими скриптами сборки, зачастую такими же запутанными и очень confuse'ными как и сам код. Если используется maven, то задача сильно упрощается. По крайней мере можно посмотреть на зависимости и проанализировать зависимости между артефактами. Если же используется ant... Сочувствую. В одной из систем с которыми я работал, различные конечные артефакты собирались фильтрованием уже скомпилированных классов. Определить в какие артефакты попадёт ваш класс просто так не получится. Поэтому есть два варианта:
    * Добавить комментарий.
    * Более предпочтительный. Использовать @deprecated. Например смысл переменной price изменился. По всей системе она используется как amount. Как будет выглядеть рефакторинг:

До
    
	public class Pojo {  
	    private Integer price;  
	    public Integer getPrice() {  
	         return price;  
	    }  
	    public void setPrice(Integer price) {  
	         this.price = price;  
	    }  
	}

После:
    
	public class Pojo {  
	    private Integer amount;  
	    /** 
	    * @deprecated use getAmount() 
	    **/  
	    @deprecated  
	    public Integer getPrice() {  
	         return amount;  
	    }  
	    /** 
	    * @deprecated use setAmount(amount) 
	    **/  
	    public void setPrice(Integer amount) {  
	         this.amount = amount;  
	    }  
	    public Integer getAmount() {  
	         return amount;  
	    }  
	    public void setAmount(Integer amount) {  
	         this.amount = amount;  
	    }  
	} 
	
  2. Использование синглетона вида: Application.getInstance(). В общем случае использование синглетонов ведёт к спагетти коду. Например в двух совершенно разных системах я обнаружил не только наличие подобных синглетонов но их их использование вида.
  
Использование:
  
	public class Pojo {  
		private Integer amount;  
		public Integer getCalculatedAmount() {  
	         Integer someDiff = Application.getInstance().getDAO().queryDBByKey(amount);  
	         return amount - someDiff;  
	    }  
	}

Разумеется поддерживать подобные вещи достаточно сложно. Зачастую эти синглетоны содержат соединения с базами данных, читают из файлов какую то информацию и делают прочие вещи. Единственным возможным эффективным образом работать с наследными системами - написание тестов перед внесением новой функциональности, для того чтобы проверить работоспособность системы после внесения изменений. С подобным использованием синглетонов модульные тесты практически невозможно написать. Однако опять же существует два способа:

  * Писать интеграционные тесты с базами данных другими сервисами и пр. Но это неудобно если нужно протестировать небольшую часть системы. 
  * Немного отрефакторить синглетон
  
До

	public class Aplication {  
	     private static Application instance;  
	  
	     private Application() {  
	     }  
	  
	     public static synchronized Application getInstace() {  
	           if(instance == null ) {  
	                  instance = new Application();  
	           }  
	           return instance;  
	     }  
	} 

После

	public class Aplication {  
	     protected static final String APPLICATION_CLASS_NAME = "application";  
	     private static Application instance;  
	  
	     private Application() {  
	     }  
	  
	     public static synchronized Application getInstace() {  
	           if(instance == null ) {  
	                  Class clazz = Class.forName(System.getProperty(APPLICATION_CLASS_NAME));  
	                  instance = (Application)clazz.newInstance();  
	           }  
	           return instance;  
	     }  
	}  
	public class ApplicationMock extends Application {  
	  
	     public void configure() {  
	          System.setProperty(APPLICATION_CLASS_NAME,ApplicationMock.class.getName());  
	     }  
	  
	}
