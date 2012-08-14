# Quick start

```
git clone git@github.com:rcs/gandolfini.git
cd gandolfini
bin/gandolfini

```

# What it is
![James Gandolfini](http://upload.wikimedia.org/wikipedia/commons/thumb/0/03/JamesGandolfiniSept11TIFF.jpg/192px-JamesGandolfiniSept11TIFF.jpg)
*An homage to the most famous bouncer of all time.*


Single page apps are cool.
Browser security models are cool.

Developing against web APIs that don't implement CORS headers isn't cool.

We can fix that now.


Gandolfini serves as a bouncer for all those APIs that you want to use but can't. Request through Gandolfini, and get your data with all the necessary bits to let you access it on the client.

## Example


Let's say we wanted to display Crunchbase data on our website, being the good web 2.3 citizens we are.


They have a nice, simple api. We'll grab the facebook info.

```javascript

jQuery.get(
  'http://api.crunchbase.com/v/1/company/facebook.js',
  function(data) {
    Object.keys(data);
  },"json");

```

And we reload the page and load the console, already feeling our Klout score rising.

Instead of our juicy facebook data, we get:
```
XMLHttpRequest cannot load http://api.crunchbase.com/v/1/company/facebook.js. Origin http://localhost:3000 is not allowed by Access-Control-Allow-Origin.
```

Lame. Let's route it through gandolfini.

```javascript
jQuery.get('http://localhost:8080/api.crunchbase.com/v/1/company/facebook.js', function()…
```

And now we've got what we want.

```
// XHR finished loading: "http://gandolfini.herokuapp.com/api.crunchbase.com/v/1/company/facebook.js". jquery.min.js:4
["name", "permalink", "crunchbase_url", "homepage_url", "blog_url", "blog_feed_url", "twitter_username", "category_code", "number_of_employees", "founded_year", "founded_month", "founded_day", "deadpooled_year", "deadpooled_month", "deadpooled_day", "deadpooled_url", "tag_list", "alias_list", "email_address", "phone_number", "description", "created_at", "updated_at", "overview", "image", "products", "relationships", "competitions", "providerships", "total_money_raised", "funding_rounds", "investments", "acquisition", "acquisitions", "offices", "milestones", "ipo", "video_embeds", "screenshots", "external_links"]
```



## Use in an existing app

Gandolfini can also be used as Connect middleware.

```javascript
http = require 'http'
connect = require 'connect'
gandolfini = require 'gandolfini'

http.createServer(
  connect()
    .use(connect.logger())
    .use(gandolfini())
  )
).listen(8080);
```


