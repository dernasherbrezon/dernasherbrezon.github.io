---
title: "IMQ Connection Concurrent Glassfish"
date: 2009-01-11T13:14:18+01:00
draft: false
tags:
  - java
  - j2ee
---
Наблюдается следующая проблема:

thread1:

	javax.jms.Connection conn = connFactory.createConnection();  
	Work connectionHandler = new MyWorker(conn);  
	WorkManager.scheduleWork(connectionHandler); 

thread2 (MyWorker):

	Session s = conn.createSession(...);  
	Consumer c = s.createConsumer(someDestination);  
	Message m = c.receive(); 

При receive JMSException и пишет что consumer closed. Однако если:

thread1:

	Work connectionHandler = new MyWorker(connFactory);  
	WorkManager.scheduleWork(connectionHandler);

thread2 (MyWorker):

	javax.jms.Connection conn = connFactory.createConnection();  
	Session s = conn.createSession(...);  
	Consumer c = s.createConsumer(someDestination);  
	Message m = c.receive(); 

То всё работает. Happy holidays  