# פקודות הרצה ועדכון לפרויקט

קובץ זה מרכז את הפקודות החשובות לעדכון המאגר מול המקור והרצת הפרויקט מקומית.

---

## 1. עדכון המאגר האישי שלך מול המאגר המקורי (Git)

כדי למשוך שינויים מהמאגר המקורי (`upstream`) ולעדכן את המאגר האישי שלך (`origin`):

```bash
# 1. מעבר לענף הראשי
git checkout main

# 2. משיכת העדכונים האחרונים מ-upstream
git pull upstream main

# 3. החלת הגדרות החתימה וה-Team ID המקומיים שלך מחדש (למקרה שהקובץ נדרס בעדכון)
Scripts/apply-local-config.py

# 4. דחיפת העדכונים למאגר האישי שלך ב-GitHub
git push origin main
```

---

## 2. בנייה והרצת הפרויקט (Swift)

הפרויקט בנוי כחבילת Swift (Swift Package) עם מספר מטרות להרצה:

### בנייה (Build)
בניית כלל רכיבי הפרויקט:
```bash
swift build
```

### הרצת האפליקציה (Gargantua)
הרצת ממשק המשתמש של Gargantua (SwiftUI app):
```bash
swift run Gargantua
```

### הרצת שרת ה-MCP (GargantuaMCP)
הרצת שרת ה-Model Context Protocol המקומי:
```bash
swift run GargantuaMCP
```

### הרצת בדיקות (Tests)
הרצת טסטים לפרויקט:
```bash
swift test
```
או באמצעות הסקריפט המובנה:
```bash
Scripts/test.sh
```

---

## 3. בנייה, אריזה וחתימה מקומית (עם תעודת מפתח שלך)

הגדרנו את קובץ `.env.release` עם ה-Team ID ותעודת החתימה שלך. כעת תוכל לבנות את האפליקציה כקובץ `.app` חתום במלואו שיוכל לרוץ מתיקיית היישומים עם הרשאות מנהל מערכת מלאות (הודות לחתימת ה-Privileged Helper):

```bash
# 1. בנייה במצב Release
swift build -c release

# 2. הרכבת ה-App Bundle (ייצור dist/Gargantua.app)
Scripts/release/assemble-app.sh

# 3. חתימת האפליקציה וכל תתי-הרכיבים שלה עם התעודה שלך
Scripts/release/sign.sh

# 4. העתקה לתיקיית היישומים (Applications)
cp -R dist/Gargantua.app /Applications/
```

