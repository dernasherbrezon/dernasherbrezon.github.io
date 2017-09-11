---
title: "Производительность Hibernate Validator"
date: 2012-04-11T13:14:18+01:00
draft: false
---
Недавно столкнулся с библиотекой Hibernate Validator и jsr 303 в частности. Ниже привожу небольшой микро-бенчмарк тестирования производительности. 
Тестовый POJO:

	public class BusinessObject {  
  
	 	@NotBlank  
	 	private String name;  
	 	@CustomNotNull(groups = { APIValidationGroup.class })  
	 	private String uuid;  
	  
	 	public String getName() {  
	  		return name;  
	 	}  
	  
	 	public void setName(String name) {  
	  		this.name = name;  
	 	}  
	  
	 	public String getUuid() {  
	  		return uuid;  
	 	}  
	  
	 	public void setUuid(String uuid) {  
	  		this.uuid = uuid;  
	 	}  
  
	}  
	
Для чистоты эксперимента и приближения к реальному сценарию я сделал кастомную валидацию, которая просто проверяет на null:

	public class CustomNotNullValidator implements ConstraintValidator<CustomNotNull, String> {  
  
	 	public void initialize(CustomNotNull constraintAnnotation) {  
	 	}  
	   
	 	public boolean isValid(String value, ConstraintValidatorContext context) {  
	  		if( value == null ) {  
	   			return false;  
	  		}  
	  		return true;  
	 	}  
	}
	
Собственно сам тест:

	public static void main(String[] args) {  
  
	 	int heatCount = 10000;  
 		int count = 1000000;  
  
 		Validator validator = Validation.buildDefaultValidatorFactory().getValidator();  
  
 		BusinessObject validObject = new BusinessObject();  
		 validObject.setName("123");  
		 validObject.setUuid("123");  
		  
		 for (int i = 0; i < heatCount; i++) {  
		  validator.validate(validObject, Default.class);  
		 }  
		  
		 long start = System.currentTimeMillis();  
		 for (int i = 0; i < count; i++) {  
		  validator.validate(validObject, Default.class);  
		 }  
		 long diff = (System.currentTimeMillis() - start);  
		 System.out.println("hibernate validation absolute: " + diff + " avg: " + ((double)diff / count));  
		  
		 for (int i = 0; i < heatCount; i++) {  
		  validate(validObject);  
		 }  
		  
		 start = System.currentTimeMillis();  
		 for (int i = 0; i < count; i++) {  
		  validate(validObject);  
		 }  
		 diff = (System.currentTimeMillis() - start);  
		 System.out.println("static validation absolute: " + diff + " avg: " + ((double)diff / count));  
		  
		 start = System.currentTimeMillis();  
		 for (int i = 0; i < count; i++) {  
		  validator.validate(validObject, APIValidationGroup.class);  
		 }  
		 diff = (System.currentTimeMillis() - start);  
		 System.out.println("hibernate custom validation absolute: " + diff + " avg: " + ((double)diff / count));  
		  
		 start = System.currentTimeMillis();  
		 for (int i = 0; i < count; i++) {  
		  validateCustom(validObject);  
		 }  
		 diff = (System.currentTimeMillis() - start);  
		 System.out.println("static custom validation absolute: " + diff + " avg: " + ((double)diff / count));  
		}  
		  
		private static boolean validate(BusinessObject obj) {  
		 if (StringUtils.isBlank(obj.getName())) {  
		  return false;  
		 }  
		 return true;  
		}  
		  
		private static boolean validateCustom(BusinessObject obj) {  
		 if (!validate(obj)) {  
		  return false;  
		 }  
		 if (obj.getUuid() == null) {  
		  return false;  
		 }  
		 return true;  
	}
	
Результаты выполнения следующие (hibernate validator 4.2.0.Final):

  * hibernate validation absolute: 2410 avg: 0.00241
  * static validation absolute: 17 avg: 1.7E-5
  * hibernate custom validation absolute: 3407 avg: 0.003407
  * static custom validation absolute: 16 avg: 1.6E-5
  
Выводы:

  1. Hibernate валидация на ровном месте даёт падение производительности в ~150 раз. Поэтому если Ваше приложение это low-latency система, то, возможно, стоит подумать сколько объектов нужно проверять и как много полей. Возможно (но не гарантированно) стоит делать проверки через static методы.
  2. Однако если посмотреть абсолютные величины, то заметно, что удобство и гибкость в настройки валидации стоит всего 0.002 миллисекунды. Если у Вас CRUD интернет приложение, то Hibernate validator будет гораздо лучшим выбором. 