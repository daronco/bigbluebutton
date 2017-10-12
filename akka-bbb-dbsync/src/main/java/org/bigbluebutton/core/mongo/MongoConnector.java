package org.bigbluebutton.core.mongo;

// import java.util.ArrayList;
// import java.util.List;
// import java.util.concurrent.BlockingQueue;
// import java.util.concurrent.Executor;
// import java.util.concurrent.Executors;
// import java.util.concurrent.LinkedBlockingQueue;
// import org.slf4j.Logger;
// import org.slf4j.LoggerFactory;
// import com.google.gson.JsonObject;
// import com.google.gson.JsonParser;

import com.mongodb.MongoClient;
import com.mongodb.MongoClientURI;
import com.mongodb.ServerAddress;

import com.mongodb.client.MongoDatabase;
// import com.mongodb.client.MongoCollection;
import com.mongodb.DB;

import org.bson.Document;
import java.util.Arrays;
import com.mongodb.Block;

import com.mongodb.client.MongoCursor;
import static com.mongodb.client.model.Filters.*;
import com.mongodb.client.result.DeleteResult;
import static com.mongodb.client.model.Updates.*;
import com.mongodb.client.result.UpdateResult;
import java.util.ArrayList;
import java.util.List;

import org.jongo.*;

public class MongoConnector {

    private DB database;

    public MongoConnector() {
        start();
    }

	  public void start() {
        try {
            database = new MongoClient().getDB("bigbluebutton");
        } catch (Exception e) {
            System.out.println("Error connecting to mongodb: " + e.getMessage());
        }
	  }

    public void stop() {
    }

    public void createMeeting(String data) {
        Jongo jongo = new Jongo(database);
        MongoCollection collection = jongo.getCollection("meetings");
        collection.insert(data);
    }
}
