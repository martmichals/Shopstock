// Base url for all API calls
import 'dart:convert';
import 'dart:io';

import 'package:shopstock/backshop/coordinate.dart';
import 'package:shopstock/backshop/local_data_handler.dart';
import 'package:shopstock/backshop/server_response_parsing.dart';
import 'package:shopstock/backshop/session_details.dart';
import 'package:shopstock/backshop/store.dart';
import 'package:shopstock/backshop/item.dart';
import 'server_response_parsing.dart';
import 'package:http/http.dart' as http;

const String ShopstockUrl = 'https://shopstock.live/api/';
const String TAG = 'apicaller - ';

// Method to get the stores in a rectangular area
Future<List<Store>> getStoresInArea(
    Coordinate southWest, Coordinate northEast) async {
  final requestUrl = '${ShopstockUrl}get_stores_in_area?lat_1=${southWest.lat}'
      '&lat_2=${northEast.lat}&long_1=${southWest.long}'
      '&long_2=${northEast.long}&key=${Session.shopstockAPIKey}';

  try {
    final request = await HttpClient().getUrl(Uri.parse(requestUrl));
    final response = await request.close();

    if (response.statusCode != 200) print(response);

    // Parse the response input stream
    var responseString = '';
    await for (var contents in response.transform(Utf8Decoder())) {
      responseString += '$contents';
    }
    return parseStoresInArea(responseString);
  } on SocketException {
    print('$TAG: No connection');
    return null;
  } on Exception {
    print('$TAG: App error in getStoresInArea');
    return null;
  }
}

// Method to get the items in a store
Future<List<Item>> getItemsInStore(int storeID) async {
  final requestUrl =
      'https://shopstock.live/api/get_item_labels?storeId=$storeID'
      '&key=${Session.shopstockAPIKey}';

  List<Item> allItems = [];
  for(Item item in Session.allItems){
    final fullItem = Item.full(item.id, item.name, item.categoryID, 0.0);
    allItems.add(fullItem);
  }

  try {
   final request = await HttpClient().getUrl(Uri.parse(requestUrl));
   final response = await request.close();

   if(response.statusCode != 200) return allItems;

   // Parse the response input stream
   var responseString = '';
   await for (var contents in response.transform(Utf8Decoder())) {
     responseString += '$contents';
   }
   if(!parseSuccessStatus(responseString)) return allItems;
   else return parseItemsWithLabels(responseString);
  } on SocketException {
    print('Application disconnected from the internet');
    return allItems;
  } on Exception {
    print('Fatal application error in getItemsInStore');
    return allItems;
  }
}

/*  Method to get and save the list of all items
    Returns true if the pull and save were successful
 */
Future<bool> getItemsCategories() async {
  final requestUrl = '${ShopstockUrl}get_items?key=${Session.shopstockAPIKey}';
  try {
    final request = await HttpClient().getUrl(Uri.parse(requestUrl));
    final response = await request.close();

    // Parse the response input stream
    var responseString = '';
    await for (var contents in response.transform(Utf8Decoder())) {
      responseString += '$contents';
    }
    // Initialize Session.assigner as well as the list of all items
    Session.assigner = createAssigner(responseString);
    Session.allItems = parseAllItems(responseString);

    return true;
  } on SocketException {
    print('$TAG: No connection');
  } on Exception {
    print('Fatal app error');
  }
  return false;
}

/*  Method to send report, returns null on success
    String with an error message otherwise
 */
Future<String> sendReport() async {
  final reportJson = Session.userReport.toJson();
  print(reportJson);
  if (reportJson == null) return 'You did not fill the time field!';

  final url = ShopstockUrl + 'send_report';
  Map<String, String> headers = {'Content-type': 'application/json'};

  int statusCode;
  try {
    http.Response response =
        await http.post(url, headers: headers, body: reportJson);
    statusCode = response.statusCode;
  } on SocketException {
    return 'Looks like you are not connected to the internet!';
  } on Exception {
    return 'Something went wrong when sending the report';
  }

  if (statusCode != 200) return 'Something went wrong when sending the report';

  return null;
}

/*  Method to log in, returns null if the log in was a success
    String with an error message otherwise
 */
Future<String> logIn(final email, final password, final stayLoggedIn) async {
  Session.isLongTermKey = stayLoggedIn;

  // Assembling the body
  final body = '{\"email\": \"$email\", \"password\": \"$password\", \"'
      'stay_logged_in\": $stayLoggedIn}';
  final url = ShopstockUrl + 'login';
  Map<String, String> headers = {'Content-type': 'application/json'};

  int statusCode;
  http.Response response;
  try {
    response = await http.post(url, headers: headers, body: body);
    statusCode = response.statusCode;
  } on SocketException {
    return 'Looks like you are not connected to the internet';
  } on Exception {
    return 'Something went wrong while logging in';
  }

  if (statusCode != 200) {
    // Error message generation for the user
    String parsedError;
    try {
      parsedError = parseError(response.body);
    } on FormatException {
      return 'Something went wrong in creating your account, please try again';
    }
    if (parsedError != null) {
      return parsedError;
    }
    return 'Something went wrong while logging in, please try once again';
  } else {
    if (!parseSuccessStatus(response.body)) return parseError(response.body);

    Session.shopstockAPIKey = parseKey(response.body);
    if (Session.isLongTermKey) {
      bool saveSuccess = await saveKey();
      if (saveSuccess) {
        return null;
      } else {
        print('API key did not save properly');
        return 'Fatal error';
      }
    } else {
      return null;
    }
  }
}

/*  Method to sign up, returns null if the sign up was a success
    String with an error message otherwise
 */
Future<String> signUp(final nickname, final email, final password) async {
  // Assembling the body
  final body = '{\"name\": \"$nickname\", \"email\": \"$email\", \"password\": '
      '\"$password\"}';
  final url = ShopstockUrl + 'create_account';
  Map<String, String> headers = {'Content-type': 'application/json'};

  int statusCode;
  http.Response response;
  try {
    response = await http.post(url, headers: headers, body: body);
    statusCode = response.statusCode;
  } on SocketException {
    return 'Looks like you are not connected to the internet';
  } on Exception {
    return 'Something went wrong while signing up';
  }

  // Error message generation for the user
  if (statusCode != 200) {
    String parsedError;
    try {
      parsedError = parseError(response.body);
    } on FormatException {
      return 'Something went wrong in creating your account, please try again';
    }
    if (parsedError != null) {
      return parsedError;
    }
    return 'Something went wrong in the account creation process, try once more';
  }
  return null;
}

// Method to logout on the server
Future<bool> logout() async {
  // Assembling the body
  final body = '{\"key\": \"${Session.shopstockAPIKey}\"}';
  final url = ShopstockUrl + 'logout';
  Map<String, String> headers = {'Content-type': 'application/json'};

  // Send the request, disregard server feedback
  try {
    http.Response response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) if (parseSuccessStatus(response.body))
      return true;
    return false;
  } on SocketException {
    return false;
  } on Exception {
    return false;
  }
}

// Method to get the expire time for an API key
// IMPORTANT: Handles the case for which the server is down
Future<DateTime> getExpireTime() async{
  final requestUrl = '${ShopstockUrl}get_expire_time?key=${Session.shopstockAPIKey}';
  try {
    final request = await HttpClient().getUrl(Uri.parse(requestUrl));
    final response = await request.close();

    // Parse the response input stream
    var responseString = '';
    await for (var contents in response.transform(Utf8Decoder())) {
      responseString += '$contents';
    }
    try {
      if(parseSuccessStatus(responseString)) {
        final unixTime = jsonDecode(responseString)['expires'] as int;
        return DateTime.fromMillisecondsSinceEpoch(unixTime * 1000);
      }
    } on Exception {
      print('There was an error parsing the server response for expire time');
    }
    return null;
  } on SocketException {
    print('$TAG: No connection');
  } on Exception {
    print('Fatal app error');
  }
  return null;
}

