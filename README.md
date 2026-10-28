# pelican-prod-env

Репозиторий с манифестом для развёртывания продакшен-окружения проекта в k8s в Docker.

Больше информации и проекте и связанных репозиториях можно найти здесь:  
[pelican-documentation](https://github.com/TourmalineCore/pelican-documentation).


## Развёртывание проекта в ВМ

### Подключение к ВМ по SSH

Установим и откроем [MobaXterm](https://mobaxterm.mobatek.net/) - отличный инструмент для работы с SSH и не только.

На странице созданной ВМ должен быть доступен её Внешний IP - это наш Remote host

В Advanced SSH Settings указываем Use private key и выбираем файл приватного ключа.

После подключения всегда сначала выполняем команду
```cli
sudo bash
```

### Конфигурация проекта

Клонируем репозиторий 

```bash
git clone --depth 1 https://github.com/TourmalineCore/pelican-prod-env
```

Переходим в репозиторий
```bash
cd pelican-prod-env
```

Создаём файл с переменными по файлу примеру
```bash
cp .devcontainer/devcontainer.env.example .devcontainer/devcontainer.env
```

Меняем доступ, чтобы файлы были доступны не только от root пользователя
```bash
chmod -R 0777 .
```

Генерируем ключи для CMS 
https://github.com/strapi/strapi/issues/15206
```bash
sed -i "s|^PELICAN_PROD_APP_KEYS=.*|PELICAN_PROD_APP_KEYS=$(openssl rand -base64 32),$(openssl rand -base64 32),$(openssl rand -base64 32)|" .devcontainer/devcontainer.env

sed -i "s|^PELICAN_PROD_API_TOKEN_SALT=.*|PELICAN_PROD_API_TOKEN_SALT=$(openssl rand -base64 32)|" .devcontainer/devcontainer.env

sed -i "s|^PELICAN_PROD_ADMIN_JWT_SECRET=.*|PELICAN_PROD_ADMIN_JWT_SECRET=$(openssl rand -base64 32)|" .devcontainer/devcontainer.env

sed -i "s|^PELICAN_PROD_TRANSFER_TOKEN_SALT=.*|PELICAN_PROD_TRANSFER_TOKEN_SALT=$(openssl rand -base64 32)|" .devcontainer/devcontainer.env

sed -i "s|^PELICAN_PROD_JWT_SECRET=.*|PELICAN_PROD_JWT_SECRET=$(openssl rand -base64 32)|" .devcontainer/devcontainer.env
```

Откройте `.devcontainer/devcontainer.env` через `MobaTextEditor` или через `nano`

```bash
nano .devcontainer/devcontainer.env
```

Замените `<TO_BE_MODIFIED!!!>` на правильные значения

Устанавливаем зависимости и создаём кластер
```bash
bash install.sh
```

### Восстановление облачного хранилища

#### Подготовка облачного хранилища

1. Откройте [Yandex Cloud Console](https://console.yandex.cloud/)
1. Перейдите в сервис `Object Storage` используя поиск (ALT + S)
1. Выберите `pelican-prod-media` -> `Безопасность` -> `Политика доступа` -> `Настроить доступ`
1. Добавьте действие `ListBucket` и нажмите кнопку `Сохранить`
> После восстановления уберите `ListBucket` из действий

#### Устанавливаем `awscli` для загрузки файлов в облачное хранилище
```bash
apt install unzip

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

unzip awscliv2.zip

sudo ./aws/install
```

#### Настраиваем `awscli`
> Замените `<TO_BE_MODIFIED!!!>` на ключи от `pelican-prod-media-bucket-service-account`
```bash
mkdir ~/.aws

cat >> ~/.aws/credentials<< EOF
[default]
aws_access_key_id  = <TO_BE_MODIFIED!!!>
aws_secret_access_key = <TO_BE_MODIFIED!!!>
EOF
```

#### Загружаем файлы в облачное хранилище
> Вручную скопируйте файл бэкапа в виртуальную машину

Распаковываем архив с бэкапом
```bash
unzip pelican-prod-s3.zip -d pelican-prod-s3-backup
```

Загружаем файлы в облачное хранилище
```bash
aws --endpoint-url https://storage.yandexcloud.net s3 sync --region ru-central1 --acl public-read ./pelican-prod-s3-backup s3://pelican-prod-media/media-assets
```

### Восстановление базы данных

Сохраняем пароль от базы данных в переменную.
> Переменная доступна только в текущей сессии
```bash
POSTGRES_PASSWORD=$(devcontainer exec --workspace-folder . kubectl get secret --namespace prod postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
```

Сохраняем текущий пароль от CMS. Он будет нужен, чтобы использовать его после восстановления.
```bash
NEW_CMS_PASSWORD=$(devcontainer exec --workspace-folder . kubectl exec postgresql-0 -n prod -- env PGPASSWORD=$POSTGRES_PASSWORD psql --no-align --tuples-only -U postgres -d pelican_db -c 'SELECT password FROM public.admin_users WHERE id = 1')
```

Копируем бэкап в под базы данных PostgreSQL
```bash
devcontainer exec --workspace-folder . kubectl cp pelican-prod-env-db.backup -n prod postgresql-0:tmp/pelican_db.backup
```

Завершаем активные подключения к базе данных
```bash
devcontainer exec --workspace-folder . kubectl exec postgresql-0 -n prod -- env PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'pelican_db';"
```

Удаляем и создаём базу данных
```bash
devcontainer exec --workspace-folder . kubectl exec postgresql-0 -n prod -- env PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -c "drop database pelican_db;"

devcontainer exec --workspace-folder . kubectl exec postgresql-0 -n prod -- env PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -c "create database pelican_db;"
```

Восстанавливаем данные из бэкапа
```bash
devcontainer exec --workspace-folder . kubectl exec -it postgresql-0 -n prod -- env PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -d pelican_db -f tmp/pelican_db.backup
```

Устанавливаем новый пароль для CMS
```bash
devcontainer exec --workspace-folder . kubectl exec postgresql-0 -n prod -- env PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres -d pelican_db -c "UPDATE public.admin_users SET password='$NEW_CMS_PASSWORD' WHERE id = 1"
```