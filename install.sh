#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

clear 2>/dev/null || true

BANNER_LINES=(
    '========================================================================'
    ' __        __   _         ____                           '
    ' \ \      / /__| |__     |  _ \ _ __ _____  ___   _      '
    "  \\ \\ /\\ / / _ \\ '_ \\    | |_) | '__/ _ \\ \\/ / | | |     "
    '   \ V  V /  __/ |_) |   |  __/| | | (_) >  <| |_| |     '
    '    \_/\_/ \___|_.__/    |_|   |_|  \___/_/\_\\__, |     '
    '                                              |___/      '
    '========================================================================'
    '                 AUTO-INSTALLER by @sacoq                  '
    '========================================================================'
)
PASTEL_COLORS=(
    $'\033[38;2;255;179;186m'
    $'\033[38;2;255;209;179m'
    $'\033[38;2;255;239;186m'
    $'\033[38;2;190;238;199m'
    $'\033[38;2;174;217;255m'
    $'\033[38;2;198;190;255m'
    $'\033[38;2;235;190;255m'
    $'\033[38;2;255;190;222m'
)

render_banner() {
    local frame="$1"
    local line line_index character_index color_index
    for line_index in "${!BANNER_LINES[@]}"; do
        line="${BANNER_LINES[$line_index]}"
        printf '\r\033[2K'
        for ((character_index = 0; character_index < ${#line}; character_index++)); do
            color_index=$(( (character_index / 6 + line_index + frame) % ${#PASTEL_COLORS[@]} ))
            printf '%b%s' "${PASTEL_COLORS[$color_index]}" "${line:$character_index:1}"
        done
        printf '%b\n' "$RESET"
    done
}

render_static_banner() {
    local line_index color
    for line_index in "${!BANNER_LINES[@]}"; do
        color="$GREEN"
        if (( line_index == 0 || line_index == 7 || line_index == 9 )); then
            color="$CYAN"
        elif (( line_index == 8 )); then
            color="$YELLOW"
        fi
        printf '%b%s%b\n' "$color" "${BANNER_LINES[$line_index]}" "$RESET"
    done
}

if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then
    for FRAME in $(seq 0 15); do
        if (( FRAME > 0 )); then
            printf '\033[%dA' "${#BANNER_LINES[@]}"
        fi
        render_banner "$FRAME"
        sleep 0.16
    done
else
    render_static_banner
fi
echo ""

function step() { echo -e "\n${YELLOW}========================================\n$1\n========================================${RESET}"; }
function success() { echo -e "${GREEN}[+] $1${RESET}"; }
function error() { echo -e "${RED}[-] $1${RESET}"; exit 1; }
function warn() { echo -e "${YELLOW}[!] $1${RESET}"; }

if [[ $EUID -ne 0 ]]; then
    error "Скрипт должен быть запущен от имени root (используйте sudo)"
fi

# Служебные команды на сервере: генератор сайта-обложки и смена домена.
install_tools() {
cat > /usr/local/sbin/tproxy-gen-site <<'PYEOF'
#!/usr/bin/env python3
"""Генератор правдоподобного сайта-обложки для tproxy-server.

Каждый запуск даёт уникальный сайт: тематика, название, город, тексты, цены,
палитра, шрифты, раскладка, SVG-графика и даты файлов выбираются случайно.
Сайт полностью статический и самодостаточный: без inline-стилей и скриптов
(их блокирует CSP relay), без форм и внешних ресурсов.

Использование: tproxy-gen-site <каталог> <домен>
Переменные: SITE_LANG=ru|en (по умолчанию ru), SITE_THEME=<ключ темы>.
"""

import html
import os
import re
import secrets
import shutil
import sys
import tempfile
import time
from datetime import datetime, timezone

R = secrets.SystemRandom()

# ---------------------------------------------------------------- тематики --

THEMES = {
    "ru": [
        {
            "key": "coffee",
            "kind": "обжарочная кофе",
            "a": ["Северная", "Тёплая", "Медленная", "Честная", "Городская", "Утренняя", "Янтарная", "Тихая"],
            "w": ["Зерно", "Турка", "Пенка", "Рассвет", "Обжарка", "Жаровня", "Крема"],
            "names": ["{a} обжарка", "Обжарочная «{w}»", "{a} чашка", "Кофе «{w}»"],
            "slug": "catalog", "nav": "Каталог",
            "taglines": ["Свежая обжарка каждую неделю", "Кофе, который обжарили вчера",
                         "Зерно из хозяйств, обжарка — у нас", "Небольшие партии, понятный вкус"],
            "hero": ["Обжариваем кофе небольшими партиями и отправляем в день обжарки. Эспрессо-смеси, фильтр и моносорта из Эфиопии, Колумбии и Бразилии.",
                     "Маленькая обжарочная в {city}. Работаем с кофейнями, офисами и теми, кто варит дома, — подберём зерно под любой способ заваривания."],
            "items": [
                ("Эфиопия Иргачеффе", "Цитрус, бергамот, жасмин. Для воронки и аэропресса.", (850, 1300), "₽ / 250 г"),
                ("Колумбия Уила", "Карамель, красное яблоко, мягкая кислотность.", (750, 1100), "₽ / 250 г"),
                ("Бразилия Серрадо", "Орех и молочный шоколад. Хорош в эспрессо и с молоком.", (650, 950), "₽ / 250 г"),
                ("Эспрессо-смесь «Дом»", "Плотное тело и сладкое послевкусие для капучино.", (700, 1000), "₽ / 250 г"),
                ("Кения АА", "Чёрная смородина, томат, яркая кислотность.", (950, 1400), "₽ / 250 г"),
                ("Декаф Колумбия", "Без кофеина, метод Swiss Water. Шоколад и сухофрукты.", (800, 1150), "₽ / 250 г"),
                ("Гватемала Антигуа", "Какао, специи, плотное тело.", (800, 1200), "₽ / 250 г"),
                ("Кофе для офиса", "Поставки от 3 кг в месяц и настройка кофемашины.", (2400, 3900), "₽ / кг"),
            ],
            "features": [
                ("Обжарка по понедельникам", "Партии до 15 кг — зерно не успевает залежаться на складе."),
                ("Доставка по городу", "Привозим в день обжарки, по России отправляем СДЭК и Почтой."),
                ("Помол под ваш способ", "Турка, гейзер, воронка, френч-пресс — смелем как нужно."),
                ("Прямые закупки", "Знаем фермы, с которыми работаем, и платим им выше биржи."),
                ("Каппинги по субботам", "Открытые дегустации новых лотов, вход свободный."),
            ],
            "about": [
                "{name} появилась в {year} году как хобби двух бариста, которым надоело покупать кофе с непонятной датой обжарки.",
                "Сегодня у нас собственный ростер на 5 кг, небольшой склад зелёного зерна и постоянные клиенты — от домашних любителей до кофеен {city}.",
                "Мы не гонимся за объёмом: каждая партия пробуется на каппинге, а профиль обжарки записывается и повторяется.",
                "Если не знаете, что выбрать, — напишите нам. Подберём зерно под ваш способ заваривания и расскажем, как его готовить.",
            ],
            "reviews": ["Лучший кофе, который я пробовал в городе. Беру Эфиопию уже полгода.",
                        "Заказываем в офис — всегда свежий, привозят вовремя.",
                        "Помогли подобрать зерно для гейзерной кофеварки, очень доволен.",
                        "Приятно, что на пачке всегда стоит дата обжарки.",
                        "Были на каппинге — интересно даже для новичка."],
            "stats": [("лет обжариваем", None), ("сортов в работе", (9, 18)), ("кг в месяц", (300, 900))],
            "hours": ["Пн–Пт 9:00–19:00, Сб 10:00–16:00", "Ежедневно 10:00–20:00", "Вт–Сб 10:00–19:00"],
        },
        {
            "key": "arch",
            "kind": "архитектурное бюро",
            "a": ["Линия", "Контур", "Плоскость", "Ось", "Модуль", "Проекция", "Штрих"],
            "w": ["Север", "Квадрат", "План", "Фасад", "Пролёт", "Атриум"],
            "names": ["Бюро «{a}»", "Студия «{w}»", "{a} — архитектура", "Мастерская «{a}»"],
            "slug": "services", "nav": "Услуги",
            "taglines": ["Архитектура и интерьеры", "Проектируем дома и интерьеры",
                         "Частные дома, квартиры, общественные пространства"],
            "hero": ["Проектируем частные дома и интерьеры в {city} и области. Ведём проект от обмеров до авторского надзора.",
                     "Небольшое бюро с полным циклом: концепция, рабочая документация, подбор подрядчиков и надзор на стройке."],
            "items": [
                ("Обмерный план", "Выезд на объект, обмеры, чертежи в DWG и PDF.", (8, 15), "тыс. ₽"),
                ("Эскизный проект интерьера", "Планировка, стиль, 3D-визуализации ключевых зон.", (1500, 2500), "₽ / м²"),
                ("Полный дизайн-проект", "Рабочие чертежи, спецификации, ведомости материалов.", (3500, 5500), "₽ / м²"),
                ("Проект частного дома", "Архитектурные решения, фасады, разрезы, узлы.", (900, 1600), "₽ / м²"),
                ("Авторский надзор", "Выезды на объект, контроль подрядчиков, корректировки.", (35, 60), "тыс. ₽ / мес"),
                ("Консультация архитектора", "Разбор планировки или участка, 1,5 часа.", (4, 7), "тыс. ₽"),
                ("Благоустройство участка", "Генплан, дорожки, освещение, озеленение.", (60, 150), "тыс. ₽"),
            ],
            "features": [
                ("Один архитектор на проект", "Вы общаетесь с автором проекта, а не с менеджером."),
                ("Сроки в договоре", "Этапы, результаты и даты фиксируем до начала работ."),
                ("Смета до стройки", "Ведомости материалов позволяют посчитать бюджет заранее."),
                ("Проверенные подрядчики", "Порекомендуем бригады, с которыми работаем не первый год."),
                ("Надзор на объекте", "Проверяем, что построено так, как нарисовано."),
            ],
            "about": [
                "Бюро {name} основано в {year} году. За это время мы спроектировали больше сотни квартир и несколько десятков частных домов.",
                "Работаем командой из архитекторов, дизайнеров и инженера-конструктора. Каждый проект ведёт один автор — от первой встречи до сдачи объекта.",
                "Нам близка спокойная архитектура: натуральные материалы, продуманный свет и планировки, в которых удобно жить.",
                "Большинство новых заказчиков приходят по рекомендациям — для нас это лучшая оценка работы.",
            ],
            "reviews": ["Сделали проект квартиры за два месяца, строители работали строго по чертежам.",
                        "Спасибо за надзор — без него ремонт растянулся бы вдвое.",
                        "Дом получился именно таким, как мы хотели, и уложились в бюджет.",
                        "Очень внимательны к деталям, все узлы проработаны.",
                        "Понравилось, что всегда на связи и объясняют решения."],
            "stats": [("лет работы", None), ("проектов", (90, 260)), ("человек в команде", (4, 9))],
            "hours": ["Пн–Пт 10:00–19:00, встречи по записи", "Пн–Пт 9:30–18:30"],
        },
        {
            "key": "bike",
            "kind": "веломастерская",
            "a": ["Втулка", "Спица", "Педаль", "Каретка", "Звезда", "Цепь", "Обод"],
            "w": ["Велодвор", "Крутилка", "Двухколёсные", "Велоточка", "Спицы и втулки"],
            "names": ["Веломастерская «{a}»", "{w}", "Мастерская «{a}»", "{w} — ремонт велосипедов"],
            "slug": "prices", "nav": "Цены",
            "taglines": ["Ремонт и обслуживание велосипедов", "Чиним быстро и честно",
                         "Сервис для шоссе, МТБ и городских велосипедов"],
            "hero": ["Обслуживаем шоссейные, горные и городские велосипеды в {city}. Большинство работ — в день обращения.",
                     "Настроим, переберём и подготовим к сезону. Работаем с амортизаторами, гидравликой и колёсами."],
            "items": [
                ("Базовое ТО", "Регулировка переключателей и тормозов, смазка цепи, проверка болтов.", (1500, 2500), "₽"),
                ("Полное ТО", "Переборка втулок, каретки, рулевой, чистка трансмиссии.", (4500, 7000), "₽"),
                ("Замена камеры или покрышки", "С учётом снятия и установки колеса.", (300, 600), "₽"),
                ("Правка колеса", "Устранение восьмёрки и натяжение спиц.", (500, 900), "₽"),
                ("Прокачка гидравлических тормозов", "Одна сторона, с заменой жидкости.", (900, 1500), "₽"),
                ("Обслуживание вилки", "Замена масла и пыльников, 50 или 200 часов.", (2500, 5500), "₽"),
                ("Сборка колеса", "Сборка на новые спицы, работа без стоимости деталей.", (2000, 3500), "₽"),
                ("Хранение зимой", "Мойка, консервация и хранение до весны.", (800, 1500), "₽ / мес"),
            ],
            "features": [
                ("Ремонт в день обращения", "Мелкие работы делаем при вас, остальное — чаще всего за сутки."),
                ("Согласуем заранее", "Сначала диагностика и смета, потом ремонт — без сюрпризов."),
                ("Запчасти в наличии", "Цепи, кассеты, тормозные колодки и покрышки популярных размеров."),
                ("Гарантия на работу", "Если что-то разрегулировалось за месяц — поправим бесплатно."),
                ("Подготовка к сезону", "Весной записываем заранее, чтобы не ждать в очереди."),
            ],
            "about": [
                "Мастерская {name} открылась в {year} году в небольшом гараже. Теперь у нас светлое помещение, три рабочих стенда и склад запчастей.",
                "Мы сами катаемся — на шоссе, по лесу и просто по {city}, — поэтому знаем, как должен работать исправный велосипед.",
                "Не навязываем лишних работ: если деталь ещё походит, так и скажем.",
                "Принимаем велосипеды любых марок, включая детские и электровелосипеды.",
            ],
            "reviews": ["Сделали ТО за день, байк едет как новый.",
                        "Честно сказали, что кассету менять рано. Приятно.",
                        "Спасли колесо после неудачного прыжка. Спасибо!",
                        "Быстро прокачали тормоза, цена как в прайсе.",
                        "Оставляю велосипед на зиму уже третий год."],
            "stats": [("лет работаем", None), ("велосипедов в год", (600, 1800)), ("мастера", (2, 4))],
            "hours": ["Вт–Вс 11:00–20:00", "Ежедневно 10:00–21:00 (апрель–октябрь)", "Пн–Сб 10:00–19:00"],
        },
        {
            "key": "translate",
            "kind": "бюро переводов",
            "a": ["Лингва", "Глосса", "Словарь", "Полиглот", "Транслит", "Контекст", "Синтаксис"],
            "w": ["Точный перевод", "Слово и дело", "Два языка", "Переводческая"],
            "names": ["Бюро переводов «{a}»", "{a}", "«{w}»", "Агентство «{a}»"],
            "slug": "services", "nav": "Услуги",
            "taglines": ["Письменные и устные переводы", "Переводы документов с заверением",
                         "Переводим с 30 языков"],
            "hero": ["Переводим документы, договоры и техническую документацию. Нотариальное заверение и апостиль в {city}.",
                     "Письменные и устные переводы для частных клиентов и компаний. Сроки и стоимость — до начала работы."],
            "items": [
                ("Перевод паспорта", "С заверением у нотариуса, готово за 1 день.", (900, 1600), "₽"),
                ("Документы об образовании", "Диплом с приложением, аттестат.", (1800, 3500), "₽"),
                ("Письменный перевод, английский", "Общая тематика, за учётную страницу.", (500, 900), "₽ / стр."),
                ("Письменный перевод, редкие языки", "Скандинавские, азиатские и другие.", (1100, 2200), "₽ / стр."),
                ("Технический перевод", "Инструкции, спецификации, чертежи.", (800, 1400), "₽ / стр."),
                ("Нотариальное заверение", "Подпись переводчика у нотариуса.", (700, 1200), "₽"),
                ("Устный последовательный перевод", "Переговоры, сделки, экскурсии.", (2500, 4500), "₽ / час"),
                ("Апостиль", "Проставление апостиля на документы.", (3500, 6000), "₽"),
            ],
            "features": [
                ("Стоимость заранее", "Считаем по фото документа за 15 минут."),
                ("Носители языка", "Для важных текстов подключаем редактора-носителя."),
                ("Срочные заказы", "Паспорт или справку переведём и заверим в тот же день."),
                ("Конфиденциальность", "Подписываем NDA, документы храним не дольше необходимого."),
                ("Работаем с компаниями", "Договор, закрывающие документы, оплата по счёту."),
            ],
            "about": [
                "{name} работает с {year} года. Мы начинали как два переводчика английского, а сейчас сотрудничаем с сорока специалистами.",
                "Каждый перевод проходит редактуру: второй переводчик сверяет терминологию, даты и имена.",
                "Нас выбирают за аккуратность и сроки — особенно когда документы нужны для визы или поступления.",
                "Офис находится в центре {city}, а заказы принимаем и дистанционно — по фото или скану.",
            ],
            "reviews": ["Перевели и заверили документы для визы за один день.",
                        "Работаем с бюро по договору, технические тексты всегда без ошибок.",
                        "Помогли с апостилем, всё объяснили по шагам.",
                        "Быстро ответили и назвали точную цену.",
                        "Перевод диплома приняли в университете без вопросов."],
            "stats": [("лет работы", None), ("языков", (25, 45)), ("страниц в месяц", (1200, 4000))],
            "hours": ["Пн–Пт 9:00–19:00, Сб 11:00–16:00", "Пн–Пт 9:00–18:00"],
        },
        {
            "key": "wood",
            "kind": "столярная мастерская",
            "a": ["Дуб", "Ясень", "Клён", "Кедр", "Орех", "Липа", "Бук"],
            "w": ["Стружка", "Верстак", "Рубанок", "Годовые кольца", "Шип-паз", "Столяр"],
            "names": ["Мастерская «{a}»", "«{w}»", "{a} и сталь", "Столярная «{w}»"],
            "slug": "works", "nav": "Изделия",
            "taglines": ["Мебель из массива на заказ", "Столы, полки и кухни из дерева",
                         "Делаем мебель, которая служит десятилетиями"],
            "hero": ["Делаем мебель из массива дуба, ясеня и ореха в своей мастерской в {city}. Каждое изделие — по вашим размерам.",
                     "Столы, стеллажи, кухни и лестницы из натурального дерева. Покрываем маслом и воском, даём гарантию."],
            "items": [
                ("Обеденный стол из дуба", "Столешница 40 мм, ножки из массива или металла.", (65, 140), "тыс. ₽"),
                ("Журнальный столик", "Массив, масло с твёрдым воском.", (22, 45), "тыс. ₽"),
                ("Стеллаж", "Открытые полки, крепление к стене.", (30, 80), "тыс. ₽"),
                ("Кухонный гарнитур", "Фасады из массива, корпуса из фанеры.", (60, 110), "тыс. ₽ / пог. м"),
                ("Подоконник или столешница", "Под размер, с обработкой кромки.", (12, 25), "тыс. ₽ / пог. м"),
                ("Лестница", "Ступени и ограждение на металлическом каркасе.", (180, 450), "тыс. ₽"),
                ("Реставрация мебели", "Снятие старого покрытия, ремонт, новое масло.", (8, 40), "тыс. ₽"),
            ],
            "features": [
                ("Своя мастерская", "Всё делаем сами — от раскроя до покрытия."),
                ("Сухая древесина", "Покупаем камерную сушку и выдерживаем доски ещё месяц."),
                ("Эскиз бесплатно", "Нарисуем изделие и посчитаем стоимость до предоплаты."),
                ("Доставка и сборка", "Привезём и соберём на месте без лишней пыли."),
                ("Гарантия 3 года", "И бесплатное обновление масла через год."),
            ],
            "about": [
                "Мастерская {name} работает с {year} года. Начинали с разделочных досок, а сегодня делаем кухни и лестницы.",
                "Мы используем только массив и качественную фанеру, без ДСП и плёнок. Покрытия — натуральные масла и воски.",
                "Каждое изделие делает один мастер, поэтому мы отвечаем за результат лично.",
                "В мастерскую в {city} можно приехать, посмотреть образцы древесины и обсудить проект за чашкой чая.",
            ],
            "reviews": ["Стол получился даже лучше, чем на эскизе.",
                        "Сделали стеллаж в нишу с кривыми стенами — идеально встал.",
                        "Кухне три года, выглядит как новая.",
                        "Отреставрировали бабушкин буфет, спасибо!",
                        "Всё по срокам, аккуратная сборка."],
            "stats": [("лет в мастерской", None), ("изделий", (300, 900)), ("пород дерева", (6, 12))],
            "hours": ["Пн–Сб 10:00–19:00, шоурум по записи", "Пн–Пт 9:00–18:00"],
        },
    ],
    "en": [
        {
            "key": "coffee",
            "kind": "coffee roastery",
            "a": ["Northern", "Slow", "Honest", "Amber", "Quiet", "Morning", "Harbour", "Copper"],
            "w": ["Bean", "Crema", "Kettle", "Roastworks", "Drum", "Origin"],
            "names": ["{a} Roasters", "{a} Coffee Co.", "The {w} Roastery", "{a} & {w}"],
            "slug": "shop", "nav": "Coffee",
            "taglines": ["Fresh roasts every week", "Small batches, clear flavours",
                         "Coffee roasted the day before it ships"],
            "hero": ["We roast in small batches and ship on roast day: espresso blends, filter and single origins from Ethiopia, Colombia and Brazil.",
                     "A small roastery in {city} working with cafés, offices and home brewers. Tell us how you brew and we will match the beans."],
            "items": [
                ("Ethiopia Yirgacheffe", "Citrus, bergamot, jasmine. Great for pour-over.", (12, 17), "€ / 250 g"),
                ("Colombia Huila", "Caramel, red apple, gentle acidity.", (11, 15), "€ / 250 g"),
                ("Brazil Cerrado", "Nuts and milk chocolate, perfect with milk.", (9, 13), "€ / 250 g"),
                ("House Espresso", "Heavy body and a sweet finish.", (10, 14), "€ / 250 g"),
                ("Kenya AA", "Blackcurrant and bright acidity.", (14, 19), "€ / 250 g"),
                ("Decaf Colombia", "Swiss Water process, chocolate and dried fruit.", (11, 15), "€ / 250 g"),
                ("Office subscription", "From 3 kg a month, machine setup included.", (32, 48), "€ / kg"),
            ],
            "features": [
                ("Roasted on Mondays", "Batches under 15 kg, so nothing sits on a shelf."),
                ("Local delivery", "Same-day delivery in town, tracked shipping everywhere else."),
                ("Ground to order", "Espresso, moka pot, pour-over or French press."),
                ("Direct trade", "We know the farms we buy from and pay above market."),
                ("Saturday cuppings", "Open tastings of new lots, free to attend."),
            ],
            "about": [
                "{name} started in {year} as a side project of two baristas who were tired of coffee with no roast date.",
                "Today we run a 5 kg roaster, a small green coffee store and supply home brewers and cafés across {city}.",
                "Every batch is cupped before it leaves, and every roast profile is logged so we can repeat it.",
                "Not sure what to pick? Drop us a line and we will suggest something for your brewer.",
            ],
            "reviews": ["Best coffee in town, I've been ordering the Ethiopia for months.",
                        "We get our office beans here — always fresh and on time.",
                        "They helped me pick beans for my moka pot. Very happy.",
                        "Love that every bag has the roast date on it.",
                        "The cupping was fun even for a beginner."],
            "stats": [("years roasting", None), ("coffees on offer", (9, 18)), ("kg per month", (300, 900))],
            "hours": ["Mon–Fri 8am–6pm, Sat 9am–2pm", "Every day 9am–7pm", "Tue–Sat 9am–5pm"],
        },
        {
            "key": "arch",
            "kind": "architecture studio",
            "a": ["Line", "Axis", "Plane", "Module", "Contour", "Section", "Grid"],
            "w": ["Studio", "Atelier", "Works", "Office", "Practice"],
            "names": ["{a} {w}", "{a} Architects", "Studio {a}", "{a} & Plan"],
            "slug": "services", "nav": "Services",
            "taglines": ["Architecture and interiors", "Houses, flats and small public spaces",
                         "Calm, well-lit, carefully detailed"],
            "hero": ["We design private houses and interiors in and around {city}, from the first survey to site supervision.",
                     "A small full-service practice: concept, construction drawings, contractor selection and on-site support."],
            "items": [
                ("Measured survey", "Site visit, measurements, DWG and PDF drawings.", (350, 700), "€"),
                ("Interior concept", "Layout, style direction and key 3D views.", (25, 40), "€ / m²"),
                ("Full interior design", "Working drawings, schedules and specifications.", (55, 85), "€ / m²"),
                ("House design", "Plans, elevations, sections and details.", (18, 30), "€ / m²"),
                ("Site supervision", "Regular visits and contractor coordination.", (600, 1100), "€ / month"),
                ("Consultation", "A 90-minute review of a plan or a plot.", (120, 200), "€"),
            ],
            "features": [
                ("One architect per project", "You work with the author, not an account manager."),
                ("Fixed milestones", "Stages, deliverables and dates are agreed up front."),
                ("Costed before build", "Material schedules let you budget early."),
                ("Trusted builders", "We recommend crews we have worked with for years."),
                ("On-site support", "We make sure it is built the way it was drawn."),
            ],
            "about": [
                "{name} was founded in {year}. Since then we have designed more than a hundred homes and a few dozen houses.",
                "We are a small team of architects, designers and a structural engineer. One person leads each project from start to finish.",
                "We like quiet architecture: natural materials, good daylight and plans that are easy to live in.",
                "Most new clients come through recommendations, which we consider the best review there is.",
            ],
            "reviews": ["They designed our flat in two months, and the builders followed the drawings to the letter.",
                        "Supervision saved us from doubling the renovation time.",
                        "The house turned out exactly as we hoped, on budget.",
                        "Great attention to detail, every junction is resolved.",
                        "Always reachable and happy to explain their decisions."],
            "stats": [("years in practice", None), ("projects", (90, 260)), ("people", (4, 9))],
            "hours": ["Mon–Fri 9am–6pm, meetings by appointment", "Mon–Fri 9:30am–5:30pm"],
        },
        {
            "key": "bike",
            "kind": "bicycle workshop",
            "a": ["Spoke", "Sprocket", "Crank", "Hub", "Chainring", "Freewheel", "Derailleur"],
            "w": ["Cycles", "Bike Works", "Wheel Shop", "Bike Garage"],
            "names": ["{a} {w}", "The {a} Shop", "{a} & Chain", "{a} {w}"],
            "slug": "prices", "nav": "Prices",
            "taglines": ["Bike repair and servicing", "Fast, honest bike repairs",
                         "Road, mountain and city bikes serviced"],
            "hero": ["We service road, mountain and city bikes in {city}. Most jobs are done the same day.",
                     "Tune-ups, overhauls, wheel builds and suspension service, done properly and priced up front."],
            "items": [
                ("Basic tune-up", "Gears and brakes adjusted, chain lubed, bolts checked.", (45, 70), "€"),
                ("Full service", "Hubs, bottom bracket and headset overhauled, drivetrain cleaned.", (120, 180), "€"),
                ("Puncture repair", "Tube or tyre replacement, labour included.", (10, 18), "€"),
                ("Wheel truing", "Remove wobbles and even out spoke tension.", (15, 25), "€"),
                ("Hydraulic brake bleed", "Per brake, fresh fluid.", (25, 40), "€"),
                ("Fork service", "Oil and seals, lower-leg or full service.", (70, 150), "€"),
                ("Winter storage", "Wash, prep and storage until spring.", (20, 35), "€ / month"),
            ],
            "features": [
                ("Same-day repairs", "Small jobs while you wait, most others within 24 hours."),
                ("Quote first", "We inspect and quote before touching anything."),
                ("Parts in stock", "Chains, cassettes, pads and common tyre sizes."),
                ("Workmanship guarantee", "Anything slips out of adjustment within a month, we fix it free."),
                ("Spring prep", "Book ahead and skip the seasonal queue."),
            ],
            "about": [
                "{name} opened in {year} in a small garage. Today we have a bright shop, three work stands and a parts store.",
                "We ride ourselves, on the road, on trails and around {city}, so we know how a healthy bike should feel.",
                "We never push unnecessary work: if a part has life left in it, we will say so.",
                "All brands welcome, including kids' bikes and e-bikes.",
            ],
            "reviews": ["Serviced in a day, rides like new.",
                        "They told me the cassette didn't need replacing yet. Honest people.",
                        "Rescued my wheel after a bad landing. Thanks!",
                        "Quick brake bleed, price exactly as listed.",
                        "Third winter storing my bike here."],
            "stats": [("years open", None), ("bikes a year", (600, 1800)), ("mechanics", (2, 4))],
            "hours": ["Tue–Sun 10am–7pm", "Mon–Sat 9am–6pm"],
        },
        {
            "key": "translate",
            "kind": "translation agency",
            "a": ["Lingua", "Glossa", "Verba", "Lexis", "Idiom", "Syntax", "Polyglot"],
            "w": ["Translations", "Language Services", "Translation Bureau"],
            "names": ["{a} {w}", "{a}", "{a} Language Co."],
            "slug": "services", "nav": "Services",
            "taglines": ["Written and spoken translation", "Certified document translation",
                         "Thirty languages, one careful team"],
            "hero": ["We translate documents, contracts and technical manuals, with certified and notarised options in {city}.",
                     "Written and interpreting services for individuals and companies. Price and deadline confirmed before we start."],
            "items": [
                ("Passport translation", "Certified, ready in one day.", (35, 60), "€"),
                ("Diplomas and transcripts", "Degree certificate with supplement.", (70, 130), "€"),
                ("General translation, EN/DE/FR", "Per standard page.", (20, 35), "€ / page"),
                ("Rare languages", "Nordic, Asian and others.", (40, 80), "€ / page"),
                ("Technical translation", "Manuals, specifications, drawings.", (30, 55), "€ / page"),
                ("Consecutive interpreting", "Meetings, negotiations, site visits.", (70, 120), "€ / hour"),
                ("Apostille assistance", "Getting your documents legalised.", (90, 160), "€"),
            ],
            "features": [
                ("Upfront pricing", "Send a photo and get an exact quote in 15 minutes."),
                ("Native editors", "Important texts are reviewed by a native speaker."),
                ("Rush orders", "Passports and certificates translated the same day."),
                ("Confidentiality", "NDAs signed on request; files kept only as long as needed."),
                ("Business accounts", "Contracts, invoices and monthly billing."),
            ],
            "about": [
                "{name} has been working since {year}. We started as two English translators and now collaborate with forty specialists.",
                "Every job is edited: a second translator checks terminology, dates and names.",
                "Clients choose us for accuracy and speed, especially when documents are needed for a visa or university.",
                "Our office is in central {city}, and we accept orders remotely by scan or photo.",
            ],
            "reviews": ["Translated and certified my visa documents in a day.",
                        "We use them for technical texts — never a mistake.",
                        "Helped with the apostille and explained every step.",
                        "Quick reply and an exact price.",
                        "My diploma translation was accepted without questions."],
            "stats": [("years", None), ("languages", (25, 45)), ("pages a month", (1200, 4000))],
            "hours": ["Mon–Fri 9am–6pm", "Mon–Fri 8:30am–5:30pm, Sat by appointment"],
        },
        {
            "key": "wood",
            "kind": "furniture workshop",
            "a": ["Oak", "Ash", "Walnut", "Maple", "Cedar", "Elm", "Birch"],
            "w": ["Joinery", "Woodworks", "Furniture", "Workshop"],
            "names": ["{a} {w}", "{a} & Iron", "The {a} {w}", "{a} House {w}"],
            "slug": "work", "nav": "Our work",
            "taglines": ["Solid wood furniture made to order", "Tables, shelving and kitchens in real wood",
                         "Furniture built to last decades"],
            "hero": ["We make solid oak, ash and walnut furniture in our own workshop in {city}, every piece to your measurements.",
                     "Tables, shelving, kitchens and stairs in natural wood, finished with oils and waxes and fully guaranteed."],
            "items": [
                ("Oak dining table", "40 mm top, solid wood or steel legs.", (1400, 3000), "€"),
                ("Coffee table", "Solid wood, hardwax oil finish.", (450, 900), "€"),
                ("Shelving unit", "Open shelves, wall-fixed.", (600, 1600), "€"),
                ("Kitchen", "Solid wood fronts, birch plywood carcasses.", (1200, 2200), "€ / m"),
                ("Worktop or window board", "Made to size, edges finished.", (250, 500), "€ / m"),
                ("Furniture restoration", "Strip, repair and refinish.", (180, 800), "€"),
            ],
            "features": [
                ("Our own workshop", "Everything from cutting to finishing is done in-house."),
                ("Properly dried timber", "Kiln-dried and then rested for another month."),
                ("Free sketch", "We draw and price your piece before any deposit."),
                ("Delivery and fitting", "Delivered and assembled without the mess."),
                ("Three-year guarantee", "Plus a free re-oiling after the first year."),
            ],
            "about": [
                "{name} has been running since {year}. We started with chopping boards and now build kitchens and staircases.",
                "We only use solid timber and quality plywood — no chipboard, no foil. Finishes are natural oils and waxes.",
                "Each piece is made by one maker, who is personally responsible for it.",
                "You are welcome to visit the workshop in {city}, see timber samples and talk the project through over tea.",
            ],
            "reviews": ["The table came out even better than the sketch.",
                        "They fitted shelving into an alcove with crooked walls — perfect.",
                        "Our kitchen is three years old and still looks new.",
                        "Restored my grandmother's sideboard beautifully.",
                        "On time and tidy fitting."],
            "stats": [("years in the workshop", None), ("pieces made", (300, 900)), ("timber species", (6, 12))],
            "hours": ["Mon–Sat 9am–6pm, showroom by appointment", "Mon–Fri 8am–5pm"],
        },
    ],
}

CITIES = {
    "ru": [("Казань", "Казани"), ("Екатеринбург", "Екатеринбурге"), ("Нижний Новгород", "Нижнем Новгороде"),
           ("Самара", "Самаре"), ("Пермь", "Перми"), ("Томск", "Томске"), ("Ярославль", "Ярославле"),
           ("Калининград", "Калининграде"), ("Тверь", "Твери"), ("Воронеж", "Воронеже"),
           ("Новосибирск", "Новосибирске"), ("Иркутск", "Иркутске"), ("Владимир", "Владимире")],
    "en": [(c, c) for c in ["Leeds", "Bristol", "Utrecht", "Ghent", "Porto", "Tallinn", "Riga", "Gdańsk",
                            "Leipzig", "Graz", "Aarhus", "Tampere", "Brno", "Ljubljana", "Cork"]],
}
STREETS = {
    "ru": ["ул. Садовая", "ул. Гагарина", "пр. Мира", "ул. Пушкина", "ул. Советская", "ул. Школьная",
           "ул. Кирова", "ул. Набережная", "ул. Заводская", "пер. Почтовый", "ул. Лесная"],
    "en": ["Mill Lane", "Station Road", "Church Street", "Harbour Street", "Victoria Road", "Park Row",
           "Canal Street", "Market Square", "Bridge Street", "Kings Road"],
}
REVIEWERS = {
    "ru": ["Анна К.", "Дмитрий", "Ольга С.", "Игорь", "Мария В.", "Алексей П.", "Екатерина", "Сергей Н.",
           "Наталья", "Павел", "Юлия Р.", "Андрей"],
    "en": ["Sarah M.", "Tom", "Lucy H.", "James", "Emma R.", "Daniel K.", "Chloe", "Mark T.", "Sophie",
           "Ben", "Hannah W.", "Oliver"],
}

UI = {
    "ru": {
        "home": "Главная", "about": "О нас", "contact": "Контакты", "privacy": "Политика конфиденциальности",
        "cta": "Связаться с нами", "more": "Все позиции", "why": "Почему мы", "reviews": "Отзывы",
        "address": "Адрес", "email": "Почта", "hours": "Часы работы", "howto": "Как нас найти",
        "howto_text": ["Вход со двора, рядом с вывеской. Парковка во дворе бесплатная.",
                       "Пять минут пешком от остановки общественного транспорта «{street}».",
                       "Второй этаж, звонок у двери. Перед визитом лучше написать нам."],
        "write": "Напишите нам — ответим в течение рабочего дня.",
        "price_note": "Цены ориентировочные. Точную стоимость назовём после уточнения деталей.",
        "from": "от", "since": "С {year} года", "rights": "Все права защищены.",
        "nf_title": "Страница не найдена", "nf_text": "Возможно, она была перемещена или вы ошиблись в адресе.",
        "nf_back": "Вернуться на главную", "facts": "В цифрах",
        "privacy_body": [
            "Настоящая политика описывает, как {name} обрабатывает персональные данные посетителей сайта {domain}.",
            "Сайт не использует cookies, счётчики посещаемости и сторонние скрипты. Мы не собираем данные автоматически.",
            "Если вы пишете нам на {email}, мы используем ваши контактные данные только для ответа и выполнения заказа и не передаём их третьим лицам, кроме случаев, предусмотренных законом.",
            "Вы можете запросить удаление своих данных, написав на {email}.",
            "Политика обновлена {date}.",
        ],
        "months": ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября",
                   "октября", "ноября", "декабря"],
    },
    "en": {
        "home": "Home", "about": "About", "contact": "Contact", "privacy": "Privacy policy",
        "cta": "Get in touch", "more": "See everything", "why": "Why us", "reviews": "What people say",
        "address": "Address", "email": "Email", "hours": "Opening hours", "howto": "Finding us",
        "howto_text": ["Entrance from the courtyard, next to the sign. Free parking on site.",
                       "A five-minute walk from the {street} stop.",
                       "First floor, ring the bell. Best to drop us a line before visiting."],
        "write": "Write to us and we will reply within one working day.",
        "price_note": "Prices are indicative; we confirm the exact cost once we know the details.",
        "from": "from", "since": "Since {year}", "rights": "All rights reserved.",
        "nf_title": "Page not found", "nf_text": "It may have moved, or the address may be mistyped.",
        "nf_back": "Back to the home page", "facts": "In numbers",
        "privacy_body": [
            "This policy explains how {name} handles personal data of visitors to {domain}.",
            "This site uses no cookies, analytics or third-party scripts. We do not collect any data automatically.",
            "If you email us at {email}, we use your contact details only to reply and fulfil your order, and never share them with third parties except where required by law.",
            "You can ask us to delete your data at any time by writing to {email}.",
            "Last updated {date}.",
        ],
        "months": ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                   "October", "November", "December"],
    },
}

FONTS = [
    ('-apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif', 'Georgia, "Times New Roman", serif'),
    ('"Helvetica Neue", Arial, sans-serif', '"Helvetica Neue", Arial, sans-serif'),
    ('system-ui, -apple-system, "Segoe UI", Roboto, sans-serif', 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif'),
    ('Georgia, "Times New Roman", serif', 'Georgia, "Times New Roman", serif'),
    ('Verdana, Geneva, sans-serif', '"Trebuchet MS", Helvetica, sans-serif'),
    ('"Segoe UI", Roboto, Ubuntu, sans-serif', '"Palatino Linotype", Palatino, "Book Antiqua", serif'),
]


def e(text):
    return html.escape(str(text), quote=True)


def fmt_price(n, lang):
    s = "{:,}".format(n)
    return s.replace(",", " ") if lang == "ru" else s


def round_nice(n):
    if n >= 1000:
        return int(round(n / 50.0) * 50)
    if n >= 100:
        return int(round(n / 10.0) * 10)
    return int(n)


# ----------------------------------------------------------------- стили ----

def make_palette():
    hue = R.randint(0, 359)
    accent_hue = (hue + R.choice([0, 25, 150, 180, 200, 330])) % 360
    dark = R.random() < 0.22
    if dark:
        return {
            "dark": True,
            "bg": "hsl({}, {}%, {}%)".format(hue, R.randint(10, 22), R.randint(8, 12)),
            "fg": "hsl({}, 15%, 92%)".format(hue),
            "muted": "hsl({}, 10%, 66%)".format(hue),
            "card": "hsl({}, {}%, {}%)".format(hue, R.randint(12, 20), R.randint(13, 17)),
            "line": "hsl({}, 12%, 24%)".format(hue),
            "accent": "hsl({}, {}%, {}%)".format(accent_hue, R.randint(50, 70), R.randint(58, 68)),
            "accent_fg": "hsl({}, 30%, 10%)".format(accent_hue),
            "soft": "hsl({}, 30%, 20%)".format(accent_hue),
            "hue": hue, "accent_hue": accent_hue,
        }
    return {
        "dark": False,
        "bg": "hsl({}, {}%, {}%)".format(hue, R.randint(15, 40), R.randint(96, 98)),
        "fg": "hsl({}, {}%, {}%)".format(hue, R.randint(15, 30), R.randint(11, 17)),
        "muted": "hsl({}, 10%, {}%)".format(hue, R.randint(38, 45)),
        "card": "#fff" if R.random() < 0.6 else "hsl({}, 30%, 99%)".format(hue),
        "line": "hsl({}, 15%, {}%)".format(hue, R.randint(86, 90)),
        "accent": "hsl({}, {}%, {}%)".format(accent_hue, R.randint(45, 72), R.randint(32, 44)),
        "accent_fg": "#fff",
        "soft": "hsl({}, {}%, {}%)".format(accent_hue, R.randint(40, 70), R.randint(90, 94)),
        "hue": hue, "accent_hue": accent_hue,
    }


def make_css(p, layout):
    body_font, head_font = layout["fonts"]
    radius = layout["radius"]
    maxw = layout["maxw"]
    card_rule = {
        "border": "border: 1px solid var(--line);",
        "shadow": "box-shadow: 0 1px 2px rgba(0,0,0,.05), 0 6px 20px rgba(0,0,0,.06);",
        "flat": "background: var(--soft);",
    }[layout["cards"]]
    head_weight = R.choice([600, 700, 800])
    h1_size = R.choice(["2.4rem", "2.7rem", "3rem", "3.2rem"])
    tracking = R.choice(["-0.02em", "-0.01em", "0", "0.01em"])
    upper_nav = "text-transform: uppercase; letter-spacing: .06em; font-size: .82rem;" if R.random() < 0.35 else ""
    hero = {
        "split": """
.hero { display: grid; grid-template-columns: 1.1fr .9fr; gap: 3rem; align-items: center; padding-top: 4.5rem; padding-bottom: 3.5rem; }
.hero img { width: 100%; height: auto; border-radius: var(--radius); }""",
        "center": """
.hero { text-align: center; padding-top: 5rem; padding-bottom: 3rem; }
.hero p.lead { margin-left: auto; margin-right: auto; }
.hero img { width: 100%; max-width: 760px; height: auto; margin: 2.5rem auto 0; display: block; border-radius: var(--radius); }""",
        "band": """
.hero { padding-top: 4rem; padding-bottom: 0; }
.hero img { width: 100%; height: 280px; object-fit: cover; margin-top: 2.5rem; display: block; border-radius: var(--radius); }""",
    }[layout["hero"]]
    header = {
        "bar": ".site-header .wrap { display: flex; justify-content: space-between; align-items: center; gap: 1rem; flex-wrap: wrap; }",
        "stack": ".site-header .wrap { display: flex; flex-direction: column; align-items: center; gap: .6rem; }\n.site-header nav { justify-content: center; }",
    }[layout["header"]]
    return """:root {{
  --bg: {bg}; --fg: {fg}; --muted: {muted}; --card: {card}; --line: {line};
  --accent: {accent}; --accent-fg: {accent_fg}; --soft: {soft};
  --radius: {radius}px; --maxw: {maxw}px;
  --font: {body_font}; --font-head: {head_font};
}}
*, *::before, *::after {{ box-sizing: border-box; }}
html {{ -webkit-text-size-adjust: 100%; }}
body {{ margin: 0; background: var(--bg); color: var(--fg); font: {fsize}/1.65 var(--font); }}
a {{ color: var(--accent); text-underline-offset: 3px; }}
a:hover {{ text-decoration-thickness: 2px; }}
img {{ max-width: 100%; }}
h1, h2, h3 {{ font-family: var(--font-head); font-weight: {hw}; letter-spacing: {tracking}; line-height: 1.2; margin: 0 0 .6em; }}
h1 {{ font-size: {h1}; }}
h2 {{ font-size: 1.7rem; }}
h3 {{ font-size: 1.12rem; }}
p {{ margin: 0 0 1em; }}
.wrap {{ max-width: var(--maxw); margin: 0 auto; padding: 0 1.25rem; }}
.site-header {{ border-bottom: 1px solid var(--line); padding: 1.1rem 0; }}
{header}
.logo {{ display: inline-flex; align-items: center; gap: .6rem; font-family: var(--font-head); font-weight: {hw}; font-size: 1.15rem; color: var(--fg); text-decoration: none; }}
.logo img {{ width: 30px; height: 30px; }}
.site-header nav {{ display: flex; gap: .4rem 1.4rem; flex-wrap: wrap; }}
.site-header nav a {{ color: var(--fg); text-decoration: none; {upper_nav} }}
.site-header nav a:hover, .site-header nav a[aria-current] {{ color: var(--accent); }}
.eyebrow {{ color: var(--accent); font-weight: 600; font-size: .9rem; margin-bottom: .8rem; }}
p.lead {{ font-size: 1.15rem; color: var(--muted); max-width: 38em; }}
{hero}
.btn {{ display: inline-block; background: var(--accent); color: var(--accent-fg); padding: .8rem 1.4rem; border-radius: calc(var(--radius) * .7); text-decoration: none; font-weight: 600; margin-top: .6rem; }}
.btn:hover {{ filter: brightness(1.08); }}
section {{ padding-top: 3rem; padding-bottom: 3rem; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 1.4rem; }}
.card {{ background: var(--card); border-radius: var(--radius); padding: 1.5rem; {card_rule} }}
.card p {{ color: var(--muted); margin: 0; }}
.price {{ font-weight: 700; color: var(--fg); white-space: nowrap; }}
.list {{ list-style: none; margin: 0; padding: 0; border-top: 1px solid var(--line); }}
.list li {{ display: flex; justify-content: space-between; gap: 1.5rem; padding: 1.1rem 0; border-bottom: 1px solid var(--line); }}
.list li p {{ color: var(--muted); margin: .2rem 0 0; }}
.note {{ color: var(--muted); font-size: .92rem; margin-top: 1.2rem; }}
.stats {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; }}
.stats div {{ padding: 1.2rem 0; border-top: 2px solid var(--accent); }}
.stats b {{ display: block; font-size: 2rem; font-family: var(--font-head); }}
.stats span {{ color: var(--muted); }}
blockquote {{ margin: 0; }}
blockquote p {{ color: var(--fg); font-style: {quote_style}; }}
blockquote footer {{ color: var(--muted); margin-top: .8rem; font-size: .92rem; }}
.two {{ display: grid; grid-template-columns: 1fr 1fr; gap: 3rem; }}
dl {{ margin: 0; }}
dt {{ font-weight: 600; margin-top: 1.1rem; }}
dd {{ margin: .2rem 0 0; color: var(--muted); }}
.page-head {{ padding-top: 3.5rem; padding-bottom: 1rem; }}
.prose {{ max-width: 44em; }}
.site-footer {{ border-top: 1px solid var(--line); margin-top: 3rem; padding: 2rem 0; color: var(--muted); font-size: .92rem; }}
.site-footer .wrap {{ display: flex; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }}
.site-footer a {{ color: var(--muted); }}
.center {{ text-align: center; padding-top: 6rem; padding-bottom: 6rem; }}
.center p.lead {{ margin-left: auto; margin-right: auto; }}
@media (max-width: 760px) {{
  h1 {{ font-size: 2.1rem; }}
  .hero, .two {{ grid-template-columns: 1fr; gap: 2rem; }}
  .hero {{ padding-top: 3rem; }}
  .list li {{ flex-direction: column; gap: .3rem; }}
}}
""".format(fsize=R.choice(["16px", "17px"]), hw=head_weight, h1=h1_size, tracking=tracking,
           upper_nav=upper_nav, hero=hero, header=header, card_rule=card_rule, radius=radius, maxw=maxw,
           body_font=body_font, head_font=head_font,
           quote_style=R.choice(["normal", "italic"]), **{k: v for k, v in p.items() if isinstance(v, str)})


# ------------------------------------------------------------------ SVG -----

def hsl(h, s, l, a=None):
    if a is None:
        return "hsl({},{}%,{}%)".format(h % 360, s, l)
    return "hsla({},{}%,{}%,{})".format(h % 360, s, l, a)


def make_hero_svg(p):
    w, h = 800, 520
    h1, h2 = p["hue"], p["accent_hue"]
    light = 30 if p["dark"] else 88
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {} {}" width="{}" height="{}">'.format(w, h, w, h)]
    parts.append('<rect width="{}" height="{}" fill="{}"/>'.format(w, h, hsl(h2, R.randint(25, 50), light)))
    style = R.choice(["blobs", "stripes", "dots", "blocks"])
    if style == "blobs":
        for _ in range(R.randint(4, 7)):
            parts.append('<circle cx="{}" cy="{}" r="{}" fill="{}"/>'.format(
                R.randint(0, w), R.randint(0, h), R.randint(60, 220),
                hsl(R.choice([h1, h2, h2 + 30]), R.randint(35, 70), R.randint(40, 75), round(R.uniform(.35, .8), 2))))
    elif style == "stripes":
        step = R.randint(38, 70)
        for i, x in enumerate(range(-h, w + h, step)):
            parts.append('<path d="M{} 0 L{} {}" stroke="{}" stroke-width="{}"/>'.format(
                x, x + h, h, hsl(h2 if i % 2 else h1, 55, 45 if not p["dark"] else 60, .5), R.randint(8, 22)))
        parts.append('<circle cx="{}" cy="{}" r="{}" fill="{}"/>'.format(
            R.randint(200, 600), R.randint(150, 370), R.randint(90, 150), hsl(h2, 60, 50)))
    elif style == "dots":
        gap = R.randint(28, 44)
        for x in range(gap // 2, w, gap):
            for y in range(gap // 2, h, gap):
                if R.random() < 0.8:
                    parts.append('<circle cx="{}" cy="{}" r="{}" fill="{}"/>'.format(
                        x, y, R.choice([2, 3, 4, 6]), hsl(R.choice([h1, h2]), 50, 45 if not p["dark"] else 65, .55)))
        parts.append('<rect x="{}" y="{}" width="{}" height="{}" rx="{}" fill="{}"/>'.format(
            R.randint(80, 300), R.randint(60, 200), R.randint(220, 380), R.randint(160, 260), R.randint(0, 40),
            hsl(h2, 55, 50, .85)))
    else:
        for _ in range(R.randint(5, 9)):
            parts.append('<rect x="{}" y="{}" width="{}" height="{}" rx="{}" fill="{}"/>'.format(
                R.randint(-50, w - 100), R.randint(-50, h - 80), R.randint(100, 320), R.randint(80, 260),
                R.choice([0, 8, 24]), hsl(R.choice([h1, h2, h2 + 20]), R.randint(30, 65), R.randint(40, 78),
                                          round(R.uniform(.4, .9), 2))))
    parts.append("</svg>\n")
    return "".join(parts)


def make_favicon(p, letter):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
            '<rect width="64" height="64" rx="{}" fill="{}"/>'
            '<text x="32" y="44" text-anchor="middle" font-family="Georgia, serif" font-size="36" '
            'font-weight="700" fill="{}">{}</text></svg>\n').format(
        R.choice([0, 12, 32]), p["accent"], p["accent_fg"], e(letter))


def logo_letter(name):
    quoted = re.search(r"«([^»]+)»", name)
    words = [w for w in re.findall(r"\w+", quoted.group(1) if quoted else name) if w.lower() != "the"]
    return (words[0] if words else name)[0].upper()


# ---------------------------------------------------------------- страницы --

def build(target, domain, lang, theme_key=None):
    ui = UI[lang]
    themes = THEMES[lang]
    if theme_key:
        matches = [t for t in themes if t["key"] == theme_key]
        if not matches:
            raise SystemExit("неизвестная тема {}; доступны: {}".format(
                theme_key, ", ".join(t["key"] for t in themes)))
        t = matches[0]
    else:
        t = R.choice(themes)

    name = R.choice(t["names"]).format(a=R.choice(t["a"]), w=R.choice(t["w"]))
    city, city_in = R.choice(CITIES[lang])
    street = R.choice(STREETS[lang])
    house = R.randint(2, 88)
    address = ("{}, {}, {}".format(city, street, house) if lang == "ru"
               else "{} {}, {}".format(house, street, city))
    now = datetime.now(timezone.utc)
    year = R.randint(2009, now.year - 3)
    labels = domain.split(".")
    mail_domain = ".".join(labels[-2:]) if len(labels) >= 2 else domain
    email = R.choice(["hello", "info", "mail", "studio", "office", "team"]) + "@" + mail_domain
    tagline = R.choice(t["taglines"])
    fmt = {"name": name, "city": city_in, "year": year}

    p = make_palette()
    layout = {
        "fonts": R.choice(FONTS),
        "radius": R.choice([0, 4, 8, 12, 18]),
        "maxw": R.choice([1040, 1100, 1160, 1200]),
        "cards": R.choice(["border", "shadow", "flat"]),
        "hero": R.choice(["split", "center", "band"]),
        "header": R.choice(["bar", "bar", "stack"]),
    }
    slug = t["slug"]

    items = []
    for title, desc, (lo, hi), unit in R.sample(t["items"], min(len(t["items"]), R.randint(6, 8))):
        base = round_nice(R.uniform(lo, hi))
        items.append((title, desc, base, unit))

    nav_items = [("/", ui["home"]), ("/" + slug, t["nav"]), ("/about", ui["about"]), ("/contact", ui["contact"])]
    css_name = R.choice(["styles.css", "style.css", "main.css", "site.css"])
    css_ver = secrets.token_hex(4)
    hero_img = R.choice(["assets/cover.svg", "img/hero.svg", "assets/header.svg", "images/main.svg"])

    def page(path, title, body, desc):
        nav = "".join(
            '<a href="{}"{}>{}</a>'.format(href, ' aria-current="page"' if href == path else "", e(label))
            for href, label in nav_items)
        full_title = name if path == "/" else "{} — {}".format(title, name)
        return """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="/{css}?v={ver}">
</head>
<body>
<header class="site-header">
<div class="wrap">
<a class="logo" href="/"><img src="/favicon.svg" alt="">{name}</a>
<nav>{nav}</nav>
</div>
</header>
<main>
{body}
</main>
<footer class="site-footer">
<div class="wrap">
<span>&copy; {year0}–{year1} {name}. {rights}</span>
<span><a href="mailto:{email}">{email}</a> · <a href="/privacy">{privacy}</a></span>
</div>
</footer>
</body>
</html>
""".format(lang=lang, title=e(full_title), desc=e(desc), css=css_name, ver=css_ver, name=e(name), nav=nav,
           body=body, year0=year, year1=now.year, rights=e(ui["rights"]), email=e(email),
           privacy=e(ui["privacy"]))

    def price_text(base, unit):
        return "{} {} {}".format(ui["from"], fmt_price(base, lang), unit)

    # главная
    features = R.sample(t["features"], 3)
    reviews = R.sample(t["reviews"], 3)
    people = R.sample(REVIEWERS[lang], 3)
    hero_text = R.choice(t["hero"]).format(**fmt)
    hero_img_tag = '<img src="/{}" alt="" width="800" height="520">'.format(hero_img)
    hero_body = """<p class="eyebrow">{eyebrow}</p>
<h1>{tagline}</h1>
<p class="lead">{text}</p>
<a class="btn" href="/contact">{cta}</a>""".format(eyebrow=e(t["kind"].capitalize() + " · " + city), tagline=e(tagline),
                                                   text=e(hero_text), cta=e(ui["cta"]))
    hero = '<section class="hero wrap"><div>{}</div>{}</section>'.format(hero_body, hero_img_tag)
    feat_html = "".join('<div class="card"><h3>{}</h3><p>{}</p></div>'.format(e(a), e(b)) for a, b in features)
    preview = "".join('<div class="card"><h3>{}</h3><p>{}</p><p class="price">{}</p></div>'.format(
        e(title), e(desc), e(price_text(base, unit))) for title, desc, base, unit in items[:3])
    rev_html = "".join('<blockquote class="card"><p>«{}»</p><footer>{}</footer></blockquote>'.format(
        e(text), e(who)) if lang == "ru" else
        '<blockquote class="card"><p>“{}”</p><footer>{}</footer></blockquote>'.format(e(text), e(who))
        for text, who in zip(reviews, people))
    sections = [
        '<section class="wrap"><h2>{}</h2><div class="grid">{}</div></section>'.format(e(ui["why"]), feat_html),
        '<section class="wrap"><h2>{}</h2><div class="grid">{}</div><p><a href="/{}">{} →</a></p></section>'.format(
            e(t["nav"]), preview, slug, e(ui["more"])),
        '<section class="wrap"><h2>{}</h2><div class="grid">{}</div></section>'.format(e(ui["reviews"]), rev_html),
    ]
    if R.random() < 0.5:
        sections[0], sections[1] = sections[1], sections[0]
    index = page("/", name, hero + "\n" + "\n".join(sections), "{} — {}. {}".format(name, t["kind"], tagline))

    # каталог / услуги
    rows = "".join('<li><div><h3>{}</h3><p>{}</p></div><span class="price">{}</span></li>'.format(
        e(title), e(desc), e(price_text(base, unit))) for title, desc, base, unit in items)
    services = page("/" + slug, t["nav"], """<section class="wrap page-head"><h1>{}</h1><p class="lead">{}</p></section>
<section class="wrap"><ul class="list">{}</ul><p class="note">{}</p></section>""".format(
        e(t["nav"]), e(tagline), rows, e(ui["price_note"])), "{}: {}".format(name, t["nav"]))

    # о нас
    about_paras = [t["about"][0]] + R.sample(t["about"][1:], R.randint(2, 3))
    stats = []
    for label, rng in t["stats"]:
        value = now.year - year if rng is None else round_nice(R.randint(*rng))
        stats.append('<div><b>{}</b><span>{}</span></div>'.format(fmt_price(value, lang), e(label)))
    about = page("/about", ui["about"], """<section class="wrap page-head"><p class="eyebrow">{}</p><h1>{}</h1></section>
<section class="wrap two"><div class="prose">{}</div><div><h2>{}</h2><div class="stats">{}</div></div></section>""".format(
        e(ui["since"].format(year=year)), e(ui["about"]),
        "".join("<p>{}</p>".format(e(x.format(**fmt))) for x in about_paras),
        e(ui["facts"]), "".join(stats)), "{} — {}".format(ui["about"], name))

    # контакты
    howto = R.choice(ui["howto_text"]).format(street=street)
    contact = page("/contact", ui["contact"], """<section class="wrap page-head"><h1>{}</h1><p class="lead">{}</p></section>
<section class="wrap two"><dl>
<dt>{}</dt><dd>{}</dd>
<dt>{}</dt><dd><a href="mailto:{}">{}</a></dd>
<dt>{}</dt><dd>{}</dd>
</dl><div><h2>{}</h2><p>{}</p></div></section>""".format(
        e(ui["contact"]), e(ui["write"]), e(ui["address"]), e(address), e(ui["email"]), e(email), e(email),
        e(ui["hours"]), e(R.choice(t["hours"])), e(ui["howto"]), e(howto)), "{}: {}".format(name, address))

    # политика
    upd = now.replace(day=1)
    upd_text = ("{} {} {} г.".format(R.randint(1, 28), ui["months"][R.randint(0, upd.month - 1)], now.year)
                if lang == "ru" else "{} {} {}".format(R.randint(1, 28), ui["months"][R.randint(0, upd.month - 1)], now.year))
    privacy = page("/privacy", ui["privacy"], '<section class="wrap page-head prose"><h1>{}</h1>{}</section>'.format(
        e(ui["privacy"]), "".join("<p>{}</p>".format(e(x.format(name=name, domain=domain, email=email, date=upd_text)))
                                  for x in ui["privacy_body"])), ui["privacy"])

    # 404
    not_found = page("/404", ui["nf_title"], '<section class="wrap center"><h1>404</h1><p class="lead">{}. {}</p><a class="btn" href="/">{}</a></section>'.format(
        e(ui["nf_title"]), e(ui["nf_text"]), e(ui["nf_back"])), ui["nf_title"])

    robots = "User-agent: *\nAllow: /\n\nSitemap: https://{}/sitemap.xml\n".format(domain)
    sitemap = ('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
               + "".join("  <url><loc>https://{}{}</loc></url>\n".format(domain, u)
                         for u in ["/", "/" + slug, "/about", "/contact", "/privacy"])
               + "</urlset>\n")

    files = {
        "index.html": index,
        slug + ".html": services,
        "about.html": about,
        "contact.html": contact,
        "privacy.html": privacy,
        "404.html": not_found,
        css_name: make_css(p, layout),
        "favicon.svg": make_favicon(p, logo_letter(name)),
        hero_img: make_hero_svg(p),
        "robots.txt": robots,
        "sitemap.xml": sitemap,
    }

    parent = os.path.dirname(os.path.abspath(target)) or "/"
    os.makedirs(parent, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".site-", dir=parent)
    # «Сайт давно живёт»: relay отдаёт Last-Modified по самому свежему файлу.
    base_ts = time.time() - R.randint(20, 300) * 86400
    for rel, content in files.items():
        full = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.chmod(full, 0o644)
        ts = base_ts + R.randint(0, 5 * 86400)
        os.utime(full, (ts, ts))
    for root, dirs, _ in os.walk(tmp):
        for d in dirs:
            os.chmod(os.path.join(root, d), 0o755)
    os.chmod(tmp, 0o755)

    if os.path.exists(target) and os.listdir(target):
        backup = "{}.bak-{}".format(target.rstrip("/"), time.strftime("%Y%m%d%H%M%S"))
        os.rename(target, backup)
        print("Старый сайт сохранён в {}".format(backup))
    elif os.path.isdir(target):
        os.rmdir(target)
    os.rename(tmp, target)
    return name, t["kind"], city


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: tproxy-gen-site <каталог> <домен>")
    lang = os.environ.get("SITE_LANG", "ru").strip().lower() or "ru"
    if lang not in THEMES:
        raise SystemExit("SITE_LANG должен быть ru или en")
    name, kind, city = build(sys.argv[1], sys.argv[2].strip().lower(), lang, os.environ.get("SITE_THEME") or None)
    print("Сайт: {} ({}, {})".format(name, kind, city))


if __name__ == "__main__":
    main()
PYEOF
chmod 0755 /usr/local/sbin/tproxy-gen-site

cat > /usr/local/sbin/tproxy-change-domain <<'CDEOF'
#!/usr/bin/env bash
# Смена домена Telegram WEB-прокси без переустановки.
#   tproxy-change-domain new.example.com
# KEEP_SITE=1 — не пересоздавать сайт-обложку, только заменить в нём домен.
# FORCE=1     — не проверять, что DNS нового домена указывает на этот сервер.
# SITE_LANG / SITE_THEME — как при установке.

set -Eeuo pipefail

INFO=/root/telegram_webproxy_info.txt
CONFIG=/etc/tproxy-server/config.json
PROFILES=/etc/tproxy-server/profiles.json
DROPIN=/etc/systemd/system/caddy.service.d/tproxy.conf
SITE=/srv/tproxy-site

say() { echo -e "\033[0;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
die() { echo -e "\033[1;31m[-] $*\033[0m" >&2; exit 1; }

normalize() {
    local d="${1,,}"
    d="${d#http://}"
    d="${d#https://}"
    d="${d%%/*}"
    printf '%s' "${d%.}"
}
current_domain() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["public_hostname"])' "$CONFIG"; }
current_secret() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["profiles"][0]["secret"])' "$PROFILES"; }

write_info() {
    local domain="$1" site="$2" secret
    secret="$(current_secret)"
    cat > "$INFO" <<EOF
========================================
       Telegram WEB Proxy by xanka
========================================

Установленные компоненты:
- MTProxy (официальное ядро на C)
- TProxy-Server (веб-ретранслятор на Go)
- Caddy (HTTPS-сервер)

Параметры:
Домен: $domain
Secret: $secret
Сайт-обложка: $site

========================================
Ссылка для подключения в Telegram:
tg://webproxy?server=$domain&secret=$secret
https://t.me/webproxy?server=$domain&secret=$secret
========================================

Сменить домен (A-запись нового домена должна указывать на этот сервер):
  tproxy-change-domain new.example.com

Пересоздать сайт-обложку (старый сохранится рядом):
  SITE_LANG=ru tproxy-gen-site $SITE $domain && systemctl restart tproxy-server
EOF
    chmod 0600 "$INFO"
}

[[ $EUID -eq 0 ]] || die "Запустите от root (sudo)."
[[ -f "$CONFIG" && -f "$PROFILES" ]] || die "WEB-прокси не установлен: нет $CONFIG."

if [[ "${1:-}" == "--write-info" ]]; then
    write_info "$(current_domain)" "${2:-}"
    exit 0
fi

[[ $# -eq 1 ]] || die "Использование: tproxy-change-domain new.example.com"

NEW="$(normalize "$1")"
[[ "$NEW" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] \
    || die "«$1» не похоже на домен."
OLD="$(current_domain)"
if [[ "$NEW" == "$OLD" ]]; then
    say "Домен уже $NEW, менять нечего."
    exit 0
fi
if [[ "${NEW%%.*}" =~ (proxy|prx|vpn|tg|telegram|mtproto|socks|tunnel) ]]; then
    warn "Поддомен «${NEW%%.*}» выдаёт назначение сервера. Лучше нейтральный: www, shop, studio, cdn и т.п."
fi

say "Смена домена: $OLD → $NEW"

# Caddy не выпустит сертификат, пока A-запись не указывает сюда.
RESOLVED="$(getent ahostsv4 "$NEW" | awk '{print $1}' | sort -u | tr '\n' ' ')"
if [[ "${FORCE:-}" != 1 ]]; then
    [[ -n "${RESOLVED// /}" ]] || die "$NEW не резолвится. Создайте A-запись на IP этого сервера и повторите (или FORCE=1)."
    MINE=" $(hostname -I 2>/dev/null || true) $(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true) "
    MATCH=""
    for IP in $RESOLVED; do
        [[ "$MINE" == *" $IP "* ]] && MATCH=1
    done
    [[ -n "$MATCH" ]] || die "$NEW указывает на ${RESOLVED% }, а это не адрес этого сервера. Исправьте DNS (или FORCE=1)."
fi

BACKUP="/root/tproxy-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"
cp -a "$CONFIG" "$DROPIN" "$BACKUP/"
[[ -f "$INFO" ]] && cp -a "$INFO" "$BACKUP/"

restore() {
    cp -a "$BACKUP/$(basename "$CONFIG")" "$CONFIG"
    cp -a "$BACKUP/$(basename "$DROPIN")" "$DROPIN"
    systemctl daemon-reload
}

python3 - "$CONFIG" "$NEW" <<'PY'
import json, sys
path, domain = sys.argv[1:]
with open(path) as fh:
    config = json.load(fh)
config["public_hostname"] = domain
# Открытие на запись сохраняет владельца и права файла.
with open(path, "w") as fh:
    json.dump(config, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
sed -i \
    -e "s|^Environment=TPROXY_HOSTNAME=.*|Environment=TPROXY_HOSTNAME=$NEW|" \
    -e "s|^Environment=ACME_EMAIL=.*|Environment=ACME_EMAIL=admin@$NEW|" \
    "$DROPIN"

if ! /usr/local/bin/tproxy-server -config "$CONFIG" -profiles-file "$PROFILES" -check; then
    restore
    die "Проверка конфигурации не прошла, вернул старый домен. Резервная копия: $BACKUP"
fi

SITE_SUMMARY="$(sed -n 's/^Сайт-обложка: //p' "$INFO" 2>/dev/null || true)"
if [[ "${KEEP_SITE:-}" != 1 && "$SITE_SUMMARY" != "свой сайт"* ]] && command -v tproxy-gen-site >/dev/null; then
    SITE_SUMMARY="$(tproxy-gen-site "$SITE" "$NEW" | tail -n1 | sed 's/^Сайт: //')" \
        || { restore; die "Не удалось сгенерировать сайт, вернул старый домен."; }
    say "Сайт: $SITE_SUMMARY"
else
    { grep -rlZF "$OLD" "$SITE" || true; } | xargs -0 -r sed -i "s/${OLD//./\\.}/$NEW/g"
    say "Домен в файлах сайта заменён."
fi

systemctl daemon-reload
systemctl restart tproxy-server caddy

say "Жду сертификат для $NEW…"
CERT=""
for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null --max-time 5 --resolve "$NEW:443:127.0.0.1" "https://$NEW/" 2>/dev/null; then
        CERT=1
        break
    fi
    sleep 2
done
if [[ -n "$CERT" ]]; then
    say "HTTPS для $NEW работает."
else
    warn "Сертификат пока не получен. Смотрите: journalctl -u caddy -n 50 (частая причина — DNS ещё не обновился или закрыт порт 80)."
fi
curl -fsS -o /dev/null http://127.0.0.1:8081/readyz || warn "Relay не готов: systemctl status tproxy-server mtproxy"

write_info "$NEW" "$SITE_SUMMARY"
echo
cat "$INFO"
echo
warn "Старые ссылки с $OLD больше не работают — раздайте новую."
say "Резервная копия старых настроек: $BACKUP"
CDEOF
chmod 0755 /usr/local/sbin/tproxy-change-domain
}

if [[ -f /root/telegram_webproxy_info.txt ]]; then
    REQUESTED="${1:-${DOMAIN:-}}"
    CURRENT="$(python3 -c 'import json; print(json.load(open("/etc/tproxy-server/config.json"))["public_hostname"])' 2>/dev/null || true)"
    if [[ -n "$REQUESTED" && -n "$CURRENT" ]]; then
        # Обновляем команды (на старых установках их может не быть) и меняем домен.
        install_tools
        exec /usr/local/sbin/tproxy-change-domain "$REQUESTED"
    fi
    warn "Прокси уже установлен! Данные находятся в файле /root/telegram_webproxy_info.txt"
    warn "Сменить домен: запустите установщик с новым доменом или tproxy-change-domain new.example.com"
    exit 0
fi

if [[ $# -ge 1 ]]; then
    DOMAIN="${1,,}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN%%/*}"
else
    DOMAIN="${DOMAIN:-}"
fi

if [[ -z "$DOMAIN" || "$DOMAIN" == "proxy.example.com" ]]; then
    if [[ "$DOMAIN" == "proxy.example.com" ]]; then
        warn "Вы указали домен-пример (proxy.example.com)."
    fi
    read -rp "$(echo -e "${BLUE}Введите ВАШ домен для прокси (А-запись должна указывать на этот сервер): ${RESET}")" DOMAIN
fi

if [[ -z "$DOMAIN" || "$DOMAIN" == "proxy.example.com" ]]; then
    error "Реальный домен не указан! Установка прервана."
fi

if [[ "${DOMAIN%%.*}" =~ (proxy|prx|vpn|tg|telegram|mtproto|socks|tunnel) ]]; then
    warn "Поддомен «${DOMAIN%%.*}» выдаёт назначение сервера. Лучше нейтральный: www, shop, studio, cdn и т.п."
fi

EMAIL="admin@${DOMAIN}"
SECRET="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
AD_TAG=""
WORKERS="${WORKERS:-1}"
MAX_CONNECTIONS="${MAX_CONNECTIONS:-4096}"
TPROXY_COMMIT="52a5feb7fac38f68da5afef9cedd9b3bfc8473ca"
MTPROXY_COMMIT="f36d8af769ffaeac36978d38c2c0f6d1104c2137"
MTPROXY_CHECKSUM="919795c416b870670841a21d1930ad97a24c7b84b9eb8c6f9e3de32f2fdf4655"
GO_VERSION="1.26.5"
GO_CHECKSUM="5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053"
CADDY_VERSION="2.11.4"
CADDY_CHECKSUM="8220d1f013b6f27510247b2360c9e0ca9f018feebd82515f07635318b34ff9777ccc8fd0b6e6f2486ce3a33fe389fbb7db12d05baa474f4587509fb4f5ebf1c9"
TEMP_PATHS=()

cleanup() {
    local path
    for path in "${TEMP_PATHS[@]}"; do
        if [[ -n "$path" && "$path" == /tmp/* ]]; then
            rm -rf -- "$path"
        fi
    done
}
trap cleanup EXIT

success "Домен: $DOMAIN"
success "Email для SSL (авто): $EMAIL"
success "Секретный ключ (авто): $SECRET"

step "Обновление системы и установка зависимостей..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl build-essential libssl-dev zlib1g-dev \
    systemd jq python3 iptables xxd nftables \
    wget unzip software-properties-common ca-certificates tar

GO_BINARY=""
if command -v go >/dev/null 2>&1; then
    GO_MINOR="$(go env GOVERSION 2>/dev/null | sed -E 's/^go1\.([0-9]+).*/\1/')"
    if [[ "$GO_MINOR" =~ ^[0-9]+$ ]] && (( GO_MINOR >= 20 )); then
        GO_BINARY="$(command -v go)"
    fi
fi
if [[ -z "$GO_BINARY" ]]; then
    GO_ARCHIVE="$(mktemp /tmp/go-linux-amd64.XXXXXX.tar.gz)"
    GO_TEMP="$(mktemp -d /tmp/go-linux-amd64.XXXXXX)"
    TEMP_PATHS+=("$GO_ARCHIVE" "$GO_TEMP")
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --output "$GO_ARCHIVE" "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    [[ "$(sha256sum "$GO_ARCHIVE" | awk '{print $1}')" == "$GO_CHECKSUM" ]] || error "Ошибка установки TProxy Server!"
    tar -C "$GO_TEMP" -xzf "$GO_ARCHIVE"
    if [[ ! -d "/opt/go${GO_VERSION}" ]]; then
        mv "$GO_TEMP/go" "/opt/go${GO_VERSION}"
    fi
    GO_BINARY="/opt/go${GO_VERSION}/bin/go"
fi
[[ -x "$GO_BINARY" ]] || error "Ошибка установки TProxy Server!"

step "Создание системных пользователей..."

if ! id -u mtproxy >/dev/null 2>&1; then useradd -r -s /usr/sbin/nologin mtproxy; fi
if ! id -u tproxy >/dev/null 2>&1;  then useradd -r -s /usr/sbin/nologin tproxy;  fi
if ! id -u caddy >/dev/null 2>&1;   then useradd -r -d /var/lib/caddy -s /usr/sbin/nologin caddy; fi

step "Установка официального ядра MTProxy..."

MTPROXY_TEMP="$(mktemp -d /tmp/mtproxy-build.XXXXXX)"
TEMP_PATHS+=("$MTPROXY_TEMP")
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --output "$MTPROXY_TEMP/MTProxy.tar.gz" \
    "https://github.com/TelegramMessenger/MTProxy/archive/${MTPROXY_COMMIT}.tar.gz"
[[ "$(sha256sum "$MTPROXY_TEMP/MTProxy.tar.gz" | awk '{print $1}')" == "$MTPROXY_CHECKSUM" ]] || error "Ошибка компиляции MTProxy!"
mkdir -p "$MTPROXY_TEMP/source"
tar -C "$MTPROXY_TEMP/source" --strip-components=1 -xzf "$MTPROXY_TEMP/MTProxy.tar.gz"
make -C "$MTPROXY_TEMP/source" -j"$(nproc)"

if [[ ! -x "$MTPROXY_TEMP/source/objs/bin/mtproto-proxy" ]]; then
    error "Ошибка компиляции MTProxy!"
fi
if [[ -d /opt/MTProxy ]]; then
    mv /opt/MTProxy "/opt/MTProxy.before-tproxy.$(date +%Y%m%d%H%M%S)"
fi
mv "$MTPROXY_TEMP/source" /opt/MTProxy
success "MTProxy успешно скомпилирован"

step "Установка TProxy Server (Web-ретранслятор)..."

export GOPATH=/root/go
export GOCACHE=/root/.cache/go-build

TPROXY_SRC="$(mktemp -d /tmp/tproxy-server.XXXXXX)"
TEMP_PATHS+=("$TPROXY_SRC")
git -C "$TPROXY_SRC" init -q
git -C "$TPROXY_SRC" remote add origin https://github.com/telegramdesktop/tproxy-server.git
git -C "$TPROXY_SRC" fetch -q --depth 1 origin "$TPROXY_COMMIT"
git -C "$TPROXY_SRC" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$TPROXY_SRC" rev-parse HEAD)" == "$TPROXY_COMMIT" ]] || error "Ошибка компиляции TProxy Server!"

(cd "$TPROXY_SRC" && "$GO_BINARY" test ./...)
(cd "$TPROXY_SRC" && CGO_ENABLED=0 "$GO_BINARY" build -trimpath -ldflags "-s -w" -o /usr/local/bin/tproxy-server ./cmd/tproxy-server)

if [[ ! -x /usr/local/bin/tproxy-server ]]; then
    error "Ошибка компиляции TProxy Server!"
fi

mkdir -p /opt/tproxy-server
rm -rf /opt/tproxy-server/deploy
cp -a "$TPROXY_SRC/deploy" /opt/tproxy-server/
success "TProxy Server установлен"

step "Установка Caddy Web Server..."

if ! command -v caddy >/dev/null 2>&1; then
    CADDY_ARCHIVE="$(mktemp /tmp/caddy-linux-amd64.XXXXXX.tar.gz)"
    CADDY_TEMP="$(mktemp -d /tmp/caddy-linux-amd64.XXXXXX)"
    TEMP_PATHS+=("$CADDY_ARCHIVE" "$CADDY_TEMP")
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --output "$CADDY_ARCHIVE" \
        "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
    [[ "$(sha512sum "$CADDY_ARCHIVE" | awk '{print $1}')" == "$CADDY_CHECKSUM" ]] || error "Ошибка установки Caddy!"
    tar -C "$CADDY_TEMP" -xzf "$CADDY_ARCHIVE"
    install -m 0755 "$CADDY_TEMP/caddy" /usr/local/bin/caddy
fi
success "Caddy установлен"

step "Настройка окружения..."

mkdir -p \
    /etc/tproxy-server \
    /etc/mtproxy \
    /srv/tproxy-site \
    /etc/caddy \
    /var/lib/caddy

chown root:tproxy /etc/tproxy-server
chmod 0750 /etc/tproxy-server
chown caddy:caddy /var/lib/caddy
chmod 0750 /var/lib/caddy
chmod 0755 /srv/tproxy-site

# Сайт-обложка. Relay отдаёт его всем, у кого нет ключа, поэтому он должен
# быть уникальным: одинаковая заглушка на всех серверах — готовая сигнатура.
install_tools

if [[ -n "${SITE_DIR:-}" ]]; then
    [[ -f "$SITE_DIR/index.html" ]] || error "В SITE_DIR=$SITE_DIR нет index.html"
    cp -a "$SITE_DIR/." /srv/tproxy-site/
    find /srv/tproxy-site -type d -exec chmod 0755 {} +
    find /srv/tproxy-site -type f -exec chmod 0644 {} +
    if grep -rqiE '<style|style="|<script>|<form' /srv/tproxy-site --include='*.html'; then
        warn "В вашем сайте есть inline-стили, inline-скрипты или формы — CSP relay их заблокирует."
    fi
    SITE_SUMMARY="свой сайт из $SITE_DIR"
else
    SITE_SUMMARY="$(SITE_LANG="${SITE_LANG:-ru}" SITE_THEME="${SITE_THEME:-}" \
        /usr/local/sbin/tproxy-gen-site /srv/tproxy-site "$DOMAIN" | tail -n1 | sed 's/^Сайт: //')" \
        || error "Ошибка генерации сайта!"
fi
chown -R root:root /srv/tproxy-site
success "Сайт-обложка: $SITE_SUMMARY"

cat > /etc/tproxy-server/config.json <<EOF
{
  "public_hostname": "$DOMAIN",
  "listen": "127.0.0.1:8080",
  "admin_listen": "127.0.0.1:8081",
  "public_dir": "/srv/tproxy-site",
  "profiles_file": "/run/credentials/tproxy-server.service/profiles.json",
  "enable_pprof": false
}
EOF

cat > /etc/tproxy-server/profiles.json <<EOF
{
  "profiles": [
    {
      "name": "default",
      "secret": "$SECRET",
      "backend": "127.0.0.1:2398"
    }
  ]
}
EOF

chown root:tproxy /etc/tproxy-server/*.json
chmod 0640 /etc/tproxy-server/config.json
chmod 0400 /etc/tproxy-server/profiles.json

curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "https://core.telegram.org/getProxySecret" -o /etc/mtproxy/proxy-secret
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "https://core.telegram.org/getProxyConfig" -o /etc/mtproxy/proxy-multi.conf
[[ "$(wc -c < /etc/mtproxy/proxy-secret)" -eq 128 ]] || error "Ошибка настройки MTProxy!"
[[ "$(wc -c < /etc/mtproxy/proxy-multi.conf)" -ge 100 ]] || error "Ошибка настройки MTProxy!"

cat > /etc/mtproxy/mtproxy.env <<EOF
MTPROXY_SECRET=$SECRET
MTPROXY_WORKERS=$WORKERS
MTPROXY_MAX_CONNECTIONS=$MAX_CONNECTIONS
EOF

chown -R root:mtproxy /etc/mtproxy
chmod 0640 /etc/mtproxy/*

step "Создание SystemD сервисов..."

install -m 0644 /opt/tproxy-server/deploy/mtproxy.service /etc/systemd/system/mtproxy.service
install -m 0644 /opt/tproxy-server/deploy/tproxy-server.service /etc/systemd/system/tproxy-server.service
install -m 0644 /opt/tproxy-server/deploy/tproxy-firewall.service /etc/systemd/system/tproxy-firewall.service
install -m 0644 /opt/tproxy-server/deploy/refresh-mtproxy-config.service /etc/systemd/system/refresh-mtproxy-config.service
install -m 0644 /opt/tproxy-server/deploy/refresh-mtproxy-config.timer /etc/systemd/system/refresh-mtproxy-config.timer
install -m 0644 /opt/tproxy-server/deploy/firewall.nft /etc/tproxy-server/firewall.nft
install -m 0755 /opt/tproxy-server/deploy/refresh-mtproxy-config.sh /usr/local/sbin/refresh-mtproxy-config
install -m 0644 /opt/tproxy-server/deploy/Caddyfile /etc/caddy/Caddyfile
install -m 0644 /opt/tproxy-server/deploy/caddy.service /etc/systemd/system/caddy.service
mkdir -p /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/tproxy.conf <<EOF
[Service]
Environment=TPROXY_HOSTNAME=$DOMAIN
Environment=TPROXY_SITE_ROOT=/srv/tproxy-site
Environment=ACME_EMAIL=$EMAIL
EOF

/usr/local/bin/tproxy-server \
    -config /etc/tproxy-server/config.json \
    -profiles-file /etc/tproxy-server/profiles.json \
    -check
TPROXY_HOSTNAME="$DOMAIN" TPROXY_SITE_ROOT=/srv/tproxy-site ACME_EMAIL="$EMAIL" \
    /usr/local/bin/caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

step "Запуск всех сервисов..."

systemctl daemon-reload
systemctl reset-failed || true
systemctl enable --now tproxy-firewall.service
systemctl enable --now mtproxy.service
systemctl restart mtproxy.service
systemctl enable --now tproxy-server.service
systemctl enable --now refresh-mtproxy-config.timer
systemctl enable --now caddy.service
systemctl restart caddy.service

for SERVICE in tproxy-firewall mtproxy tproxy-server caddy; do
    systemctl is-active --quiet "$SERVICE.service" || error "Ошибка запуска сервисов!"
done

READY=""
for ATTEMPT in $(seq 1 20); do
    if curl --fail --silent --output /dev/null http://127.0.0.1:8081/readyz; then
        READY="1"
        break
    fi
    sleep 1
done
[[ -n "$READY" ]] || error "Ошибка запуска сервисов!"

/usr/local/sbin/tproxy-change-domain --write-info "$SITE_SUMMARY"

echo -e "\n${GREEN}========================================${RESET}"
echo -e "${GREEN}      УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!      ${RESET}"
echo -e "${GREEN}========================================${RESET}"
cat /root/telegram_webproxy_info.txt
