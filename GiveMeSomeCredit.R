library(ggplot2)
library(nortest)
library(modeest)
library(dplyr)
library(caret)
library(multilevelPSA)

########################################
##########  CARGA DE DATOS   ###########
########################################

# Cargamos los datos de Kaggle
train.data <- read.csv(file = './data/cs-training.csv', header = TRUE, sep = ',')
test.data <- read.csv(file = './data/cs-test.csv', header = TRUE, sep = ',')

#Cambiamos los tipos de las columnas del dataset acorde a la especificacion
train.data$SeriousDlqin2yrs <- as.factor(train.data$SeriousDlqin2yrs)

#Cambiamos el nombre de la columna que tiene el numero de fila en ambos datasets
colnames(train.data)[1] <- c('Fila')
colnames(test.data)[1] <- c('Fila')

##################################################################
#########   PREPARACION DATOS ###################################
##################################################################

###### TRATAMIENTO NAS

#Identificamos aquellas columnas que tienen algun NA
str(lapply(train.data, function(col) any(is.na(col))))
#Vemos que las unicas features que tienen NA son 'MonthlyIncome' y 'NumberofDependents'

#Para ver como rellenar estos NAs, vamos a realizar un PCA del dataset inicial 
#eliminando las filas con NAs para ver si hay alguna feature
#que tenga alta correlacion con una componente principal y utilizar estas features para rellenar los NAs
#Quitamos tambien la variable a predecir
data.no.nas <- train.data[,-1:-2]
data.no.nas <- data.no.nas[apply(data.no.nas, 1, function(row){all(!is.na(row))}),]
pr.out = prcomp(data.no.nas, scale=TRUE)

#Vemos el porcentaje de variabilidad explicada y vemos que las 4 primeras PC cubren el 67.47%
pr.var <- pr.out$sdev^2
pve <- pr.var/sum(pr.var)
cumsum(pve) * 100
plot(pve, type = 'b')

#Analizamos las correlaciones de las features con las 4 PCs
pr.out$rotation[,1:4]

#Vemos que las correlaciones significativas son:
# NumberOfOpenCreditLinesAndLoans con PC2 (64.6%)
# NumberRealEstateLoansOrLines con PC2 (63.7%)
# age con PC3 (65.5%)

# Utilizaremos estas 3 variables como modelo para rellenar los NAs
# tanto de 'MonthlyIncome' como de 'NumberofDependents'

#########################################################################

#MonthlyIncome
#Filtramos dataset quitando los NA en esta feature
income.no.nas <- train.data[!is.na(train.data$MonthlyIncome),]
income.nas <- train.data[is.na(train.data$MonthlyIncome),]


fill.MonthlyIncome <- function(row){
  
  #Filtro income.no.nas con los valores de la fila actual
  filter.row <- income.no.nas[income.no.nas$age == row$age &
                              income.no.nas$NumberOfOpenCreditLinesAndLoans == row$NumberOfOpenCreditLinesAndLoans &
                              income.no.nas$NumberRealEstateLoansOrLines == row$NumberRealEstateLoansOrLines,]
  
  #En el caso que el filtro no nos de ningun resultado previo, 
  #filtraremos solo con age que es el valor mas correlado acorde al analisis PCA realizado
  if(length(filter.row$MonthlyIncome) == 0){
    filter.row <- income.no.nas[income.no.nas$age == row$age,]
  }
  
  #Filtro lillie.test necesita una muestra mayor que 4
  #Si hay menos datos, insertamos la mediana para rellenar el NA
  
  #Aquellos valores que no hayan sido filtrados por no existir ejemplos previos
  #(EJ: Hay un NA para una mujer de 107 años y no hay ejemplos para rellenarlo)
  #se trataran despues uno a uno
  
  #Pasamos test de normalidad (Confianza de un 0.5)
  #   SI --> Rellenamos con la media
  #   NO --> Rellenamos con la mediana
  if(length(filter.row$MonthlyIncome) > 4){
    fill.data <- round(ifelse(lillie.test(filter.row$MonthlyIncome)$p.value > 0.05, 
                             mean(filter.row$MonthlyIncome), median(filter.row$MonthlyIncome))) 
  } else {
    fill.data <- mean(filter.row$MonthlyIncome)
  } 
  
  return(data.frame(Fila=row$Fila, MonthlyIncome=fill.data))
}

#Aplicar para todas las filas
monthlyincomes.nas <- sapply(1:nrow(income.nas), function(n){fill.MonthlyIncome(income.nas[n,])})

#Añadimos los valores monthlyincome.nas en el dataset income.nas
income.nas$MonthlyIncome <- as.integer(round(unlist(monthlyincomes.nas[2,])))
                                  
#Valores con NaN que debemos solventar
income.nas[is.na(income.nas$MonthlyIncome),]

#Al no tener registros con esas edades para filtrar, 
#vamos a coger todos los registros con age > 90
filter.age <- income.nas[income.nas$age > 90 & income.nas$age < 105,]$MonthlyIncome
income.nas[is.na(income.nas$MonthlyIncome),]$MonthlyIncome <- as.integer(round(median(filter.age, na.rm = TRUE)))

#Todos los NAs completados
sum(is.na(income.nas$MonthlyIncome))

#########################################################################

#NumberOfDependents

#Filtramos dataset quitando los NA en esta feature
dependentens.no.nas <- train.data[!is.na(train.data$NumberOfDependents),]
dependentens.nas <- train.data[is.na(train.data$NumberOfDependents),]


fill.NumberOfDependents <- function(row){
  
  #Filtro income.no.nas con los valores de la fila actual
  filter.row <- dependentens.no.nas[dependentens.no.nas$age == row$age &
                                    dependentens.no.nas$NumberOfOpenCreditLinesAndLoans == row$NumberOfOpenCreditLinesAndLoans &
                                    dependentens.no.nas$NumberRealEstateLoansOrLines == row$NumberRealEstateLoansOrLines,]
  
  #En el caso que el filtro no nos de ningun resultado previo, 
  #filtraremos solo con age que es el valor mas correlado acorde al analisis PCA realizado
  if(length(filter.row$NumberOfDependents) == 0){
    filter.row <- dependentens.no.nas[dependentens.no.nas$age == row$age,]
  }
  
  #Devolvemos la mediana
  fill.data <- median(filter.row$NumberOfDependents)

  return(data.frame(Fila=row$Fila, NumberOfDependents=fill.data))
}

#Aplicar para todas las filas
numberofdependentens.nas <- sapply(1:nrow(dependentens.nas), function(n){fill.NumberOfDependents(dependentens.nas[n,])})

#Añadimos los valores numberofdependentens.nas en el dataset dependentens.nas
dependentens.nas$NumberOfDependents <- as.integer(round(unlist(numberofdependentens.nas[2,])))

#Valores con NaN que debemos solventar
dependentens.nas[is.na(dependentens.nas$NumberOfDependents),]

#Al no tener registros con esas edades para filtrar, vamos a coger todos los registros con age > 90
filter.age <- dependentens.nas[dependentens.nas$age > 90 & dependentens.nas$age < 105,]$NumberOfDependents
dependentens.nas[is.na(dependentens.nas$NumberOfDependents),]$NumberOfDependents <- as.integer(round(median(filter.age, na.rm = TRUE)))

#Todos los NAs completados
sum(is.na(dependentens.nas$NumberOfDependents))

#########################################################

#Añadimos tanto income.nas como dependentens.nas al dataset de training
train.data[is.na(train.data$MonthlyIncome),]$MonthlyIncome <- income.nas$MonthlyIncome
train.data[is.na(train.data$NumberOfDependents),]$NumberOfDependents <- dependentens.nas$NumberOfDependents

#Eliminados los NAs en el data set
sum(is.na(train.data))

###############################
#### LIMPIEZA DE TEST
###############################


########## MonthlyIncome

#Filtramos dataset quitando los NA en esta feature tomando como referencia el dataset de training
income.no.nas <- test.data[!is.na(test.data$MonthlyIncome),]
income.nas <- test.data[is.na(test.data$MonthlyIncome),]

#Aplicar para todas las filas
monthlyincomes.nas <- sapply(1:nrow(income.nas), function(n){fill.MonthlyIncome(income.nas[n,])})

#Añadimos los valores monthlyincome.nas en el dataset income.nas
income.nas$MonthlyIncome <- as.integer(round(unlist(monthlyincomes.nas[2,])))

#Valores con NaN que debemos solventar
income.nas[is.na(income.nas$MonthlyIncome),]

#Al no tener registros con esas edades para filtrar, 
#vamos a coger todos los registros con age > 90
filter.age <- income.nas[income.nas$age > 90 & income.nas$age < 105,]$MonthlyIncome
income.nas[is.na(income.nas$MonthlyIncome),]$MonthlyIncome <- as.integer(round(median(filter.age, na.rm = TRUE)))

#Todos los NAs completados
sum(is.na(income.nas$MonthlyIncome))

########## MonthlyIncome

#Filtramos dataset quitando los NA en esta feature
dependentens.no.nas <- test.data[!is.na(test.data$NumberOfDependents),]
dependentens.nas <- test.data[is.na(test.data$NumberOfDependents),]

#Aplicar para todas las filas
numberofdependentens.nas <- sapply(1:nrow(dependentens.nas), function(n){fill.NumberOfDependents(dependentens.nas[n,])})

#Añadimos los valores numberofdependentens.nas en el dataset dependentens.nas
dependentens.nas$NumberOfDependents <- as.integer(round(unlist(numberofdependentens.nas[2,])))

#Valores con NaN que debemos solventar
dependentens.nas[is.na(dependentens.nas$NumberOfDependents),]

#Todos los NAs completados
sum(is.na(dependentens.nas$NumberOfDependents))

#########################################################

#Añadimos tanto income.nas como dependentens.nas al dataset de test
test.data[is.na(test.data$MonthlyIncome),]$MonthlyIncome <- income.nas$MonthlyIncome
test.data[is.na(test.data$NumberOfDependents),]$NumberOfDependents <- dependentens.nas$NumberOfDependents

#Eliminados los NAs en el data set
sum(is.na(test.data[,3:12]))

########################################
#########   CREACION MODELO   ##########
########################################

set.seed(1234)

################ CREANDO LAS PARTICIONES DE DATOS

#Partimos en 3 folds la muestra inicial de forma aleatoria
#debido a problemas de memoria para llevar a cabo el modelo
#con todo el train.data entero
split.data <- createFolds(train.data$SeriousDlqin2yrs, list = TRUE, k = 4)
partial.training <- train.data[split.data$Fold1,]

#Creamos el sample 80/20
inTrain <- createDataPartition(partial.training$SeriousDlqin2yrs, p=0.8, list=FALSE)
training <- partial.training[inTrain,]
testing <- partial.training[-inTrain,]

#Los porcentajes de la clase predictora SeriousDlqin2yrs 
#tanto en training como testing, son similares
prop.table(table(training$SeriousDlqin2yrs))
prop.table(table(testing$SeriousDlqin2yrs))

################ MODELOS CON TODOS LOS ALGORITMOS

#Configuramos el TrainControl
BootControl <- trainControl(method = 'cv', number = 10, repeats = 3)

#Entrenamiento con los diferentes algoritmos

#Naive Bayes
nb.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                method = 'nb', trControl = BootControl,
                tuneGrid = expand.grid(.fL=c(0, 1), .usekernel=c(FALSE, TRUE)))

#SVM Lineal - Limitamos a 2 folds por capacidad de memoria
svm.linear.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                        method='svmLinear', trControl = trainControl(method='cv', number=2, repeats=3),
                        prob.model=TRUE,
                        tuneGrid = data.frame(.C=c(1)))

#SVM Polynomial - Limitamos a 2 folds por capacidad de memoria
svm.poly.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                        method='svmPoly', trControl = trainControl(method='cv', number=2, repeats=3),
                        prob.model=TRUE,
                        tuneGrid = data.frame(.degree = c(2), 
                                              .scale = c(0.10),
                                              .C = c(8)))
   
#SVM Radial - Limitamos a 2 folds por capacidad de memoria
svm.radial.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                        method='svmRadial', trControl = trainControl(method='cv', number=2, repeats=3),
                        prob.model=TRUE,
                        tuneGrid = data.frame(.sigma = c(0.25),
                                              .C = c(1)))

#Neural network
nn.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                method='nnet', trControl = BootControl, tuneLength = 10)

#Decision trees
tree.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                  method='C5.0', trControl = BootControl, tuneLength = 5)

#Random Forest
rf.fit <- train(x = training[,3:12], y = training$SeriousDlqin2yrs, 
                method = 'rf', trControl = BootControl, tuneLength = 5)

######################## COMPARACION DE MODELOs

#Comparamos los modelos en base al numero de Folds usados en
#el entrenamiento del modelo

resamps <- resamples(list(NB = nb.fit,
                          NN = nn.fit,
                          TREE = tree.fit,
                          RF = rf.fit))

summary(resamps)
bwplot(resamps)

resamps.svm <- resamples(list(SVM.Linear = svm.linear.fit,
                              SVM.Polynomial = svm.poly.fit,
                              SVM.Radial = svm.radial.fit))

summary(resamps.svm)
bwplot(resamps.svm)

######################## PREDICCION Y VOLCADO PARA SUBMISSION

#Ej con el modelo red neuronal
bestModel <- nn.fit

#Predecimos test.data para cada uno de los modelos entrenados
pred <- predict(bestModel$finalModel, test.data[,3:12])

#Guardamos en un csv para el submit
result <- data.frame(Id = 1:nrow(pred), Probability = pred[,1])

#Volcando datos en fichero
write.table(result, file = "submissions/sample.submission.csv", quote = F,
            sep = ",", row.names = FALSE)

####################### RESULTADOS KAGGLE

# Naive Bayes --> 0.795783
# SVM linear --> 0.771191
# SVM polynomial --> 0.76370616
# SVM radial --> 0.6702341
# Neural network --> 0.853331
# Decision Tree --> 0.845903
# randomForest --> 0.840396

