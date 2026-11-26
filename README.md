# גיבוי: העותקים של ה-PRs של Gesher מלפני השינוי ברישיון

Gesher עבר לרישיון קנייני ב-25.11.2026 ב-11:39 לפי UTC, ובערב אותו יום המאגר שלו הפסיק להיות ציבורי. הענף הזה שומר את הראש של כל PR כפי שהיה לפני השינוי. מותר להשתמש רק בגרסאות האלה (`NOTICE.md`, ‏`docs/he/07-upstream-sync.md`).

`snapshots.tsv`: מספר ה-PR והקומיט שלו. כל קומיט בשרשרת של הענף הזה מוסיף הורה אחד, ולכן כל הקומיטים של כל ה-PRs נשמרים כאן.

שחזור במאגר מקומי:

    git fetch origin archive/apache-snapshots
    git show FETCH_HEAD:snapshots.tsv | while IFS="$(printf '\t')" read -r pr sha; do git update-ref "refs/apache-snapshot/pr/$pr" "$sha"; done
