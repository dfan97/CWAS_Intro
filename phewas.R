library(RMySQL)
library(dplyr)
library(truncnorm)

con <- dbConnect(MySQL(), user = "root", password = "root", dbname = "PheWAS", unix.sock="/Applications/MAMP/tmp/mysql/mysql.sock")
df <- dbReadTable(conn = con, name = "data")

# Introduces some dependence into comorbidities by dividing into subpopulation of diabetics
# that's "sicker" and one that's "less sick". Here all of cohort is diabetic. Function called only on diabetics
simulateComorbid <- function(n) {
  # one-coin flip for each comorbidity, rows of data frame are people
  prob <- rep(0, 5)
  mat <- matrix (rep(0, 5 * n), byrow = TRUE, nrow = n)
  for (i in 1:n) {
    # if diabetic is "sicker", odds of each are slightly higher by 0.1
    if (runif(1) < 0.5) {
      prob <- c(0.77, 0.3, 0.2, 0.3, 0.4)
      # if diabetic is "less sick", odds of each are slightly lower by 0.1
    } else {
      prob <- c(0.57, 0.1, 0, 0.1, 0.2)
    }
    mat[i, ] <- rbinom(n = 5, size = 1, prob)
  }
  return(mat)
}

# hypertension(401), retinopathy(362.0), coronary heart disease(411), myocardial infarction(410), congestive heart failure(428)
simulateDiabeticCohort <- function(n) {
  mat <- as.data.frame(matrix(rep(0, nrow(df) * n), byrow = TRUE, nrow = n))
  names(mat) <- paste("i", df$icd9, sep = "")
  for (i in 1:n) {
    mat[i, 1:ncol(mat)] <- replicate((ncol(mat)), rbinom(n = 1, size = 1, rtruncnorm(1, a = 0, b = 1, mean = 0, sd = 0.0001)))
    # first five columns are the comorbidities
    comorbidities <- simulateComorbid(1)
    mat[i, "i401"] = comorbidities[1];
    mat[i, "i362.0"] = comorbidities[2];
    mat[i, "i411"] = comorbidities[3];
    mat[i, "i410"] = comorbidities[4];
    mat[i, "i428"] = comorbidities[5];
  }
  return(mat)
}

diabICD9s <- simulateDiabeticCohort(50)
# apply mean() to columns (denoted by 2) to double-check probabilities add up right
apply(diabICD9s[ , c("i401", "i362.0", "i411", "i410", "i428")], 2, mean)

# Partitions population into diabetic and non-diabetic, applies simulateDiabeticCohort() to diabetics
# and something else for non-diabetics
simulateControlCohort <- function(n) {
  # not-discrete so don't do Gaussian noises
  # 9.3% of the population has diabetes type 2 according to diabetes.org
  mat <- as.data.frame(matrix(rep(0, nrow(df) * n), byrow = TRUE, nrow = n))
  names(mat) <- paste("i", df$icd9, sep = "")
  for (i in 1:n) {
    if (runif(1) < 0.093) {
      mat[i, ] <- simulateDiabeticCohort(1) 
    } else {
        # picked normal because most values are close to the mean
        # truncated normal to be within 0 and 1
        mat[i, ] <- replicate(ncol(mat), rbinom(n = 1, size = 1, rtruncnorm(1, a = 0, b = 1, mean = 0, sd = 0.0001)))
    }
  }
  return(mat)
}


normICD9s <- simulateControlCohort(20)
# 2 means to columns
apply(normICD9s[ , c("i401", "i362.0", "i411", "i410", "i428")], 2, mean)

# Takes two data frames as parameters: rows are individuals and columns are ICD9 codes
oddsRatio <- function(case, control) {
  # convert everything to be categorical
  combo <- lapply(rbind(case, control), as.factor)
  #combo <- as.data.frame(lapply(rbind(case, control), as.factor))
  logReg <- glm(combo$i250 ~ combo$i401 + combo$i362.0 + combo$i411 + combo$i410 + combo$i428, data = combo, family = "binomial")
  # ~. 
  #!names(combo) == "i250"
  # reverse the log to get odds-ratio
  exp(coef(logReg))
}

sum(simulateDiabeticCohort(100)[1, ])
mean(simulateDiabeticCohort(75))
sum(simulateControlCohort(100)[1, ])
mean(simulateControlCohort(75))
a <- simulateDiabeticCohort(5)
a[1:5, 1:5]
colnames(a)
class(colnames(a)[1:5])


# n > 100 takes super long. If n < 10 ish there might not not be two categorical levels (either all 0s or all 1s but not both)
# 0.9353100     0.9850593     0.8667482     1.0250185     0.9645915     0.9679675 
oddsRatio(simulateDiabeticCohort(500), simulateControlCohort(500))

# Always disconnect at the end
dbDisconnect(con)