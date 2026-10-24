const { Client, logger, Variables } = require("camunda-external-task-client-js");

// configuration for the Client:
//  - 'baseUrl': url to the Workflow Engine
//  - 'logger': utility to automatically log important events
const config = { baseUrl: "http://camunda:8080/engine-rest", use: logger, asyncResponseTimeout:50000, maxTasks:1, workerId: "train-booking-worker" };

// create a Client instance with custom configuration
const client = new Client(config);

const bookingCache = new Map();

// susbscribe to the topic: 'BookTrain'
client.subscribe("BookTrain", async function({ task, taskService }) { 
  try {
    // Put your business logic and create variables
    const processVariables = new Variables();
    const id = bookingCache.get(task.id) || create_UUID();
    bookingCache.set(task.id, id);
    processVariables.set("TrainBookingStatus", "Confirmed");
    processVariables.set("TrainBookingID", id);
    // complete the task
    await taskService.complete(task, processVariables);
    console.log(`Train booking was finished: ${id} ...`);
  } catch (err) {
    const retries = (task.retries != null ? task.retries : 1) - 1;
    await taskService.handleFailure(task, {
      errorMessage: err.message,
      errorDetails: err.stack,
      retries: retries < 0 ? 0 : retries,
      retryTimeout: 1000
    });
  }
});

// susbscribe to the topic: 'CancelTrainBooking'
client.subscribe("CancelTrainBooking", async function({ task, taskService }) {
  try {
    //create variables
    const processVariables = new Variables();
    processVariables.set("TrainBookingStatus", "Canceled");
    //complete the task
    await taskService.complete(task, processVariables);
    const id = task.variables.get('TrainBookingID');
    console.log(`Train booking was canceled: ${id} ...`);
  } catch (err) {
    const retries = (task.retries != null ? task.retries : 1) - 1;
    await taskService.handleFailure(task, {
      errorMessage: err.message,
      errorDetails: err.stack,
      retries: retries < 0 ? 0 : retries,
      retryTimeout: 1000
    });
  }
});

function create_UUID(){
  var dt = new Date().getTime();
  var uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = (dt + Math.random()*16)%16 | 0;
      dt = Math.floor(dt/16);
      return (c=='x' ? r :(r&0x3|0x8)).toString(16);
  });
  return uuid;
}