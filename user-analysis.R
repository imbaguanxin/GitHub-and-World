
#title: "user analysis"
#author: "Guan.Xin"
#date: "2019/4/8"

  
# r setup
library(tidyverse)
library(jsonlite)
library(httpuv)
library(httr)
library(mongolite)
library(tidytext)
library(reshape2)
library(wordcloud)

# db for users
db.user <- mongo(collection = "userWithRepo", db = "github", url = "mongodb://localhost:27123")
# db for repositories
db.repo <- mongo(collection = "repos", db = "github", url = "mongodb://localhost:27123")
# db for users we haven't fetch followers
db.userUnfetched <- mongo(collection = "unfetched", db = "github", url = "mongodb://localhost:27123")

# export mongodb to a data frame with query
mongo_to_df_query <- function(database, query){
  db_list <- database$find(query)
  df <- db_list %>% as_tibble()
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
# --------------------------------------------------------------------------

# User data from mongodb
user_df <- mongo_to_df(db.user) %>% na.omit()

# change data in character to numeric
user_df$followers <- user_df$followers %>% as.numeric()
user_df$following <- user_df$following %>% as.numeric()
user_df$public_repos <- user_df$public_repos %>% as.numeric()
user_df$public_gists <- user_df$public_gists %>% as.numeric()

user_readable_df <- user_df[,-c(3:16)]
# --------------------------------------------------------------------------


# Where are those users

## Location Image
# omit people with no locations and people with NAs
only_location <- user_readable_df %>% filter(location != "") %>% na.omit()
# split the location out
only_location <- only_location$location %>% toString() %>% 
  str_split(pattern = ",") %>% unlist %>% str_trim()
# count location
only_location <- data.frame(only_location) %>% 
  group_by(only_location) %>% count() %>% arrange(desc(n))
# draw location on a word cloud
only_location %>% with(
  wordcloud(only_location, n, max.words = 100, colors=brewer.pal(8, "Dark2")))
# --------------------------------------------------------------------------

## locations plot
user_with_location <- user_readable_df %>% filter(location != "")
user_with_location$location <- user_with_location$location %>% str_extract("^([^,|\\\\/])+") %>% unlist()
user_with_location <- user_with_location %>% group_by(location)
# This is location with number of people there
location_count <- user_with_location %>% count %>% arrange(desc(n))
# Top 20 location
top_location <- location_count %>% head(n = 20)
# Percentage of people from that location
top_location$percentage <- (top_location$n / user_with_location %>% nrow) %>% round(digits = 4) * 100

# Percentage of people in each location. Only top 15 locations are ploted
ggplot(data = top_location, 
       mapping = aes(x = reorder(location, -percentage), y = percentage, fill = location)) +
  geom_bar(stat = "identity") +
  theme(axis.text.x = element_text(size = 8, vjust = 1, hjust = 1, angle = 60)) +
  labs(x = "location", y = "percentage (%)") + 
  geom_text(aes(label = percentage), size = 3) +
  theme(legend.position="top")

# a pie chart of people in top 10 locations.
# NOTE: I just selected top 10 locations and draw them in a pie chart
#       It doesn't mean that all users are from those 10 locations.
#       As shown in the fisrt bar chart, the location with most pepole accounts for
#       about 5% of total people.
ggplot(data = head(top_location, 10), mapping = aes(x = factor(1), y = n, fill = location)) +
  geom_bar(width = 1, stat = "identity") +
  coord_polar(theta = "y") +
  theme_void()
# --------------------------------------------------------------------------


# bio info text mining
# find out all the words in the bio description
bios <- user_readable_df$bio  %>% toString() %>% 
  str_remove_all("@|\\b[A-Z]\\b|\\b[A-Z]?[a-z]{1,3}\\b") %>%
  str_split("[ ,-]") %>% unlist %>% 
  str_remove_all(" |with|like|that|from|about|since|love|make|things|more|build|\\bs\\b|\\W|[0-9]+") %>% 
  str_trim() %>%
  tolower()
# count all the words
bios <- data.frame(bios, stringsAsFactors = FALSE) %>% 
  group_by(bios) %>% count() %>% arrange(desc(n))
# omit the first one which is a space and then draw the word cloud
bios[-1,] %>% with(wordcloud(bios, n, max.words = 50, colors=brewer.pal(8, "Dark2")))

# draw a bar chart of the words
ggplot(data = bios[-1,] %>% head(20), 
       mapping = aes(x = reorder(bios, -n), y = n, fill = bios)) +
  geom_bar(stat = "identity") +
  theme(axis.text.x = element_text(size = 8, vjust = 1, hjust = 1, angle = 60)) +
  labs(x = "Word In Bios", y = "Frequency")+
  theme(legend.position="top")
# --------------------------------------------------------------------------


# Catagorize people
# find out people with bios and company information
bio_df <- user_readable_df %>% filter(bio != "", company !="")
# find out people in a university
bio_df$university <- bio_df$company %>% str_detect("(C|c)ollege|(I|i)nstitute|(U|u)niversity|(S|s)chool|(A|a)cademy|.*U\\b|U.*\\b|UC|ETH|Tech|(S|s)tanford")
# find out people refer themselves as a professor
bio_df$professor <- bio_df$bio %>% str_detect("(P|p)rof(essor)?|prof\\.|(S|s)cientist|(r|R)esearcher")
# find out people refer themselves as a student
bio_df$student <- bio_df$bio %>%
  str_detect("(S|s)tudent|(c|C)andidate|(p|P)\\.?(H|h)\\.?(d|D)\\.?")
# find out people refer themselves as an engineer
bio_df$engineer <- bio_df$bio %>% 
  str_detect("(E|e)ngineer")

# find out all the companies
companys <- bio_df$company %>% str_remove_all("@") %>% tolower()  %>%
  str_split("[,-/\\|]") %>% unlist %>% str_trim() %>%
  str_remove_all("\\b(com|inc|io|http(:|s:?)?|llc|ltd|io|www|net|org)\\b|[^\\w\\s]")
companys <- data.frame(companys, stringsAsFactors = FALSE) %>% 
  group_by(companys) %>% count() %>% arrange(desc(n))
# draw the word cloud of companies
companys[-1,] %>% with(wordcloud(companys, n, max.words = 50, colors=brewer.pal(8, "Dark2")))
# --------------------------------------------------------------------------



# deal with outlier: data out of 3 standard deviation is omitted
outlier <- function(df, variable_name){
  mean <- mean(df[,variable_name])
  threeSd <- sd(df[,variable_name]) * 3
  print(sprintf("mean: %f, sd: %f", mean, threeSd/3))
  df <- df %>% filter(df[variable_name] < mean + threeSd)
  df <- df %>% filter(df[variable_name] > mean - threeSd)
  df
}

# clean the data
clean_following <- outlier(user_readable_df, "following")
# find out the porpotion of people have less than 250 following: 94%
user_readable_df %>% filter(following < 250) %>% count / (user_readable_df %>% count())
# find out the porpotion of people have less than 100 following: 84%
user_readable_df %>% filter(following < 100) %>% count / (user_readable_df %>% count())

# the distribution of user's number of following
ggplot(data = clean_following %>% filter(following < 250)) +
  geom_histogram(mapping = aes(x = following, y = ..density..), bins = 20) +
  geom_density(mapping = aes(x = following), bins = 20)
# the relationship between following and followers
ggplot(data = clean_following) +
  geom_smooth(mapping = aes(x = following, y = followers)) 

# correlation when followers is smaller than 100: 0.287
low_following <- clean_following %>%
  filter(followers < 100, following < 100)
cor(low_following$following, low_following$followers) 
# correlation when followers and following are big: -0.019
high_following <- clean_following %>%
  filter(followers > 100, following > 100)
cor(high_following$following, high_following$followers) 
# --------------------------------------------------------------------------


# Relate user with their repositories
# gett all the repo's id and its owner's id
get_repo_with_owner <- function(db = db.repo){
  df <- db$find('{}', field = '{"id" : true, "owner.id" : true, "_id" : false }')
  df$id <- df$id %>% sapply(unlist)
  df$owner <- df$owner$id %>% unlist
  return(df)
}
# build a repo_user data frame where user's numerical and catagorical information included
repo_user <- get_repo_with_owner()
bio_df <- bio_df %>% select(id, public_repos, public_gists, following, followers, student, professor, engineer, university)
colnames(bio_df)[1] <- "owner"
bio_df$owner <- bio_df$owner %>% as.numeric()
repo_user <- inner_join(repo_user, bio_df, by = "owner")

# find out a given repo id from database named db.repo
# return a data frame has columes of id, name, fork, size, stargazers count,
# watchers count, language, has pages, forks count, archived, disabled and
# open issues count.
# some of the fields may be NA
find_repo <- function(repo_id, db = db.repo){
  query <- sprintf('{ "id" : %s }', repo_id)
  repo_df <- db$find(query) %>% select(-owner)
  fields <- c("id","name","fork","size","stargazers_count",
              "watchers_count","language", "has_pages", 
              "forks_count", "archived", "disabled",
              "open_issues_count")
  repo_df <- repo_df %>% select(fields)
  for(i in 1:12){
    if (repo_df[[i]] %>% class == "data.frame"){
      repo_df[i] <- NA
    } else {
      repo_df[i] <- repo_df[[i]] %>% unlist
    }
  }
  repo_df$has_pages <- repo_df$has_pages %>% unlist
  return(repo_df)
}

# Find a user's repo given user's id
# return a data frame.
find_user_repo <- function(user_id, db = db.repo, reference = repo_user){
  repo_id <- reference %>% filter(owner == user_id) %>% select(id)
  repo_id <- repo_id$id
  repo_df <- data.frame()
  for (i in 1 : length(repo_id)){
    repo_entry <- find_repo(repo_id[i], db)
    repo_df <-  rbind(repo_df, find_repo(repo_id[i], db))
  }
  repo_df
}

# find out all the repo's id
repo_id_vec <- repo_user$id
repo_df <- data.frame()
# find repo's information. 
for (i in 1:length(repo_id_vec)){
  repo_df <- rbind(repo_df, find_repo(repo_id_vec[i]))
}
# join user and repo so that an entry shows not only the repo's information but also the user's
temp <- inner_join(repo_user, repo_df, by = "id")
write.csv(temp, file = "repo_user2.csv",row.names = FALSE)


