.PHONY: help test clean deploy

help:
	@echo "Доступные команды:"
	@echo "  make test    - Запустить тесты структуры проекта"
	@echo "  make clean   - Очистить временные файлы и логи"
	@echo "  make deploy  - Запустить основной скрипт развертывания"

test:
	@bash tests/structure_test.sh

clean:
	@rm -rf logs/*.log
	@rm -rf tmp/
	@echo "Очистка завершена"

deploy:
	@bash bin/deploy.sh