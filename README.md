```
$ docker-compose up web
$ docker-compose run web rake db:migrate
```

Then:

Contrast output of:

```
$ docker-compose run web rake db:schema:dump fail=no && cat db/schema.rb | grep foo
$ docker-compose run web rake db:schema:dump fail=yes && cat db/schema.rb | grep foo
```



