#title: "web crawler"
#author: "Guan.Xin"
#date: "2019/4/8"

# GitHub Api and Data Collection
  
# In this part, we made use of GitHub Api to fetch user and repositories information. 

# r setup
library(tidyverse)
library(jsonlite)
library(httpuv)
library(httr)
library(mongolite)
# ------------------------------------------------------------------------------------------------------


# Set Up github API
oauth_endpoints("github")
projectApp <- oauth_app(appname = "GuanXin_Github_and_World",
                        key = "1151cd623b25dc65040b",
                        secret = "5343cd60555c10ccbeb6ace4adf8594b887f3024")

#projectApp <- oauth_app(appname = "JamesgeziqianGitOAuthApp",
#                        key = "885b524769dc6bef013f",
#                        secret = "ebac8d1117a038c5facb0a9f8d2be38833d37c60")

github_token <- oauth2.0_token(oauth_endpoints("github"), projectApp)
gtoken <- config(token = github_token)

# This function helps get something manually
github_get <- function(path){
  url <- modify_url("https://api.github.com", path = path)
  GET(url, gtoken)
}

# This function get a json file from given url
github_get_with_url<- function(path){
  req <- GET(path, gtoken) 
  stop_for_status(req)
  req <- req %>% content %>% jsonlite::toJSON()
  return(req)
}
# ------------------------------------------------------------------------------------------------------


# connect to database

# db for users
db.user <- mongo(collection = "users", db = "github", url = "mongodb://localhost:27123")
# db for repositories
db.repo <- mongo(collection = "repos", db = "github", url = "mongodb://localhost:27123")
# db for users we haven't fetch followers
db.userUnfetched <- mongo(collection = "unfetched", db = "github", url = "mongodb://localhost:27123")
# db for user finished with repo fetched
db.userWithRepo <- mongo(collection = "userWithRepo", db = "github", url = "mongodb://localhost:27123")
# db for user without repo fetched
db.userNoRepo <- mongo(collection = "userNoRepo", db = "github", url = "mongodb://localhost:27123")
# ------------------------------------------------------------------------------------------------------



# functions to process user information

store_user_to_db <- function(dest_db, check_db, user_url){
  # get user informationg from github
  user_json <- github_get_with_url(user_url)
  user_list <- jsonlite::fromJSON(user_json)
  user_id <- user_list[["id"]]
  user_name <- user_list[["name"]]
  print(sprintf("user id: %s, user name: %s", user_id, user_name))
  # find id in mongoDB
  query <- sprintf('{"id" : %s}', user_id)
  if(dest_db$find(query) %>% nrow() == 0 &&
     check_db$find(query) %>% nrow() == 0){
    dest_db$insert(user_json)
    return(TRUE)
  }
  return(FALSE)
}

# store one's foller to a specific data base
get_follers_by_id <- function(user_id, fromDB = db.userUnfetched){
  query <- sprintf('{"id" : %s}', user_id)
  followers_url <- c()
  # find given id in the database
  df <- fromDB$find(query)
  # if find given user
  if (df %>% length > 0){
    # get given id's follower url (one url)
    followers_url <- df[["followers_url"]] %>% unlist
    df <- github_get_with_url(followers_url[1]) %>% fromJSON()
    # get given id's followers's url (many urls)
    followers_url <- df[["url"]] %>% unlist
    # if follers are more than 0, store all follers to userUnfetched
    if (followers_url %>% length() > 0){
      for(i in 1:length(followers_url)){
        store_user_to_db(dest_db = db.userUnfetched,
                         check_db = db.user,
                         followers_url[i])
      }
      # perfectly fetched follers
      return (0)
    } else {
      # if there are no follers, return 1
      return (1)
    }
  }
  # if not find given user, return -1
  return (-1)
}

# store one's following to a specific data base
get_follering_by_id <- function(user_id, fromDB = db.userUnfetched){
  query <- sprintf('{"id" : %s}', user_id)
  foing_url <- c()
  # find given id in the database
  df <- fromDB$find(query)
  # if find given user
  if (df %>% length > 0){
    # get given id's following url (one url)
    foing_url <- df[["following_url"]] %>% unlist %>%
      str_remove("(\\{\\/other_user\\})")
    print(foing_url[1])
    df <- github_get_with_url(foing_url[1]) %>% fromJSON()
    # get given id's following's url (many urls)
    foing_url <- df[["url"]] %>% unlist
    # if follers are more than 0, store all follers to userUnfetched
    if (foing_url %>% length() > 0){
      for(i in 1:length(foing_url)){
        store_user_to_db(dest_db = db.userUnfetched,
                         check_db = db.user,
                         foing_url[i])
      }
      # perfectly fetched follers
      return (0)
    } else {
      # if there are no follers, return 1
      return (1)
    }
  }
  # if not find given user, return -1
  return (-1)
}

# move a user, if no user in fromDB, return -1
# if there is duplicated user in toDB, renew it and return 1
# if there is no duplication in toDB, move and return 0
move_user <- function(user_id, fromDB = db.userUnfetched, toDB = db.user){
  result <- 0
  fetch_query <- sprintf('{"id" : %s}', user_id)
  df <- fromDB$find(fetch_query)
  if (df %>% length() == 0){
    return(-1)
  } else {
    if (toDB$find(fetch_query) %>% length() > 0){
      toDB$remove(fetch_query)
      result <- 1
    }
    toDB$insert(df)
    fromDB$remove(fetch_query)
    return(result)
  }
}

# copy a user, if no user in fromDB, return -1
# if there is duplicated user in toDB, renew it and return 1
# if there is no duplication in toDB, copy and return 0
copy_user <- function(user_id, fromDB, toDB){
  result <- 0
  fetch_query <- sprintf('{"id" : %s}', user_id)
  df <- fromDB$find(fetch_query)
  if (df %>% length() == 0){
    return(-1)
  } else {
    if (toDB$find(fetch_query) %>% length() > 0){
      toDB$remove(fetch_query)
      result <- 1
    }
    toDB$insert(df)
    print(result)
    return(result)
  }
}

# fetch users following and followers given a vector of user id.
fetch_users<- function(id_vec){
  for(i in 1:length(id_vec)){
    get_follering_by_id(id_vec[i])
    get_follers_by_id(id_vec[i])
    print("finish fetching one person")
    copy_user(id_vec[i], fromDB = db.userUnfetched, toDB = db.userNoRepo)
    print("finish copying to userNoRepo")
    move_user(id_vec[i])
  }
}

get_all_user_id <- function(db = db.userUnfetched){
  df <- db$find('{}')
  return(df[["id"]] %>% unlist)
}
# ------------------------------------------------------------------------------------------------------



# export mongoDB

# export mongodb to a data frame with query
mongo_to_df_query <- function(database, query){
  db_list <- database$find(query)
  df <- db_list %>% as.tibble()
  df <- apply(df, 2, as.character) %>% data.frame(stringsAsFactors = F)
  for(name in names(df)){
    df[, name] <- str_replace_all(df[,name], pattern = "list\\(\\)", replacement = "")
  }
  return(df)
}

# export mongodb as a data frame
mongo_to_df <- function(database){
  return(mongo_to_df_query(database, '{}'))
}

# print nongodb to a csv file  
mongo_to_csv <- function(database, file_name){
  df <- mongo_to_df(database)
  write.csv(df, file = file_name, row.names = F)  
}
# ------------------------------------------------------------------------------------------------------

# set up
store_user_to_db(user_url = "https://api.github.com/users/imbaguanxin", dest_db = db.userUnfetched, check_db = db.user)
follower <- get_follers_by_id(33470168, db.userUnfetched)
following <- get_follering_by_id(33470168)
# mongo_to_csv(db.userUnfetched, "user.csv")
# ------------------------------------------------------------------------------------------------------


# fetch
```{r}
id_vec <- get_all_user_id()
fetch_users(id_vec)
# mongo_to_csv(db.userUnfetched, "user.csv")
# ------------------------------------------------------------------------------------------------------

# move all userUnfetched to userNoRepo
id_vec <- get_all_user_id(db = db.userUnfetched)
for(i in 1:length(id_vec)){
  move_user(id_vec[i], fromDB = db.userUnfetched, toDB = db.userNoRepo)
}
# ------------------------------------------------------------------------------------------------------



# funtions to store repositories

# copy user to user no repo
#id_vec <- get_all_user_id(db = db.user)
#for(i in 1:length(id_vec)) {
#  copy_user(id_vec[i], db.user, db.userNoRepo)
#}

# fetch given user's repos
id_get_repo <- function(id_vec, toDB = db.repo, id_from_DB, id_to_DB){
  for(i in 1:length(id_vec)){
    user_id <- id_vec[i]
    query <- sprintf('{"id" : %s}', user_id)
    user_df <- id_from_DB$find(query)
    if (user_df %>% length > 0){
      repo_url <- user_df[["repos_url"]] %>% unlist
      print(repo_url)
      repos_json <- github_get_with_url(repo_url) %>% fromJSON
      if(repos_json %>% length > 0) {
        toDB$insert(repos_json)
      }
    }
    move_user(id_vec[i], fromDB = id_from_DB, toDB = id_to_DB)
  }
}

# fetch user's repo from userNoRepo data base
id_vec <- get_all_user_id(db = db.userNoRepo)
id_vec <- id_vec[-1]
id_get_repo(id_vec, toDB = db.repo, id_from_DB = db.userNoRepo, id_to_DB = db.userWithRepo)
# ------------------------------------------------------------------------------------------------------



# export to df and csv
df <- mongo_to_df(db.user)
df <- df %>% rbind(mongo_to_df(db.userUnfetched))
df <- df[, -c(3:16)]

df$followers <- df$followers %>% as.numeric()
df$following <- df$following %>% as.numeric()
df <- df %>% arrange(desc(followers))
df <- df %>% arrange(desc(following))

ggplot(data = df) +
  geom_point(mapping = aes(x = followers, y = following), position = "jitter")
# ------------------------------------------------------------------------------------------------------


# timer

# repeat fetching user
timer <- function(interval = 3601){
  id_vec <- get_all_user_id()
  fetch_users(id_vec)
  later::later(timer, interval)
}
# ------------------------------------------------------------------------------------------------------

