# Модели n-грамм для детектора раскладки

`LayoutSwitcher/Resources/ngram-<lang>.bin` — символьные триграммные модели
(квантованные −log₂ p(c | a b), по байту на триграмму). Генерируются скриптом
`build_ngram.py` из частотных списков слов проекта
[hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords)
(OpenSubtitles 2018, лицензия CC-BY-SA 4.0).

```bash
mkdir corpus && cd corpus
for l in ru en uk de; do
  curl -LO "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/$l/${l}_50k.txt"
done
cd ..
python3 scripts/ngram/build_ngram.py corpus LayoutSwitcher/Resources          # собрать модели
python3 scripts/ngram/build_ngram.py corpus /tmp/ngram-tune --tune            # таблица порогов
```

Детектор сравнивает правдоподобие слова «как набрано» в модели текущего языка
с правдоподобием его конверсии в модели другого языка. Порог 2.0 (log₂ на
переход) даёт на отложенной выборке ~0.1 % ложных срабатываний и ~97 %
распознавания для пары ru/en. Добавить язык = добавить алфавит в `ALPHABETS`,
скачать список и пересобрать.
