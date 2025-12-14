# Screenshots für Benutzerhandbuch

Dieses Verzeichnis enthält alle Screenshots für das BENUTZERHANDBUCH.md.

## Dateinamen-Konvention

Die Screenshots sind durchnummeriert (01-15) in der Reihenfolge ihres Auftretens im Handbuch:

### Teilnehmer-Sektion (01-06)
- `01-verlosung-uebersicht-widget.png` - Verlosungs-Übersicht mit Status-Widget
- `02-paket-los-kaufen-button.png` - Paket-Beitrag mit "Los ziehen" Button
- `03-teilnehmerliste.png` - Teilnehmerliste unter einem Paket
- `04-gewinner-benachrichtigung.png` - Persönliche Nachricht bei Gewinn
- `05-gewinner-anzeige-paket.png` - Gewinner-Anzeige bei einem Paket
- `06-erhaltungsbericht-button.png` - "Erhaltungsbericht schreiben" Button

### Ersteller-Sektion (07-15)
- `07-neue-verlosung-button.png` - "Neue Verlosung" Button in Kategorie
- `08-erstellungsformular.png` - Verlosungs-Erstellungsformular
- `09-entwurf-bearbeiten.png` - Entwurf mit Bearbeiten-Buttons
- `10-entwurf-veroeffentlichen.png` - Entwurfs-Status mit "Veröffentlichen" Button
- `11-aktive-verlosung-teilnehmer.png` - Aktive Verlosung mit Teilnehmerliste
- `12-gewinner-ziehen-button.png` - "Gewinner ziehen" Button nach Ablauf
- `13-ziehungs-modal.png` - Ziehungs-Modal
- `14-als-erhalten-markieren-button.png` - "Als erhalten markieren" Button
- `15-paket-erhalten-status.png` - Paket mit "Erhalten am" Status

## Workflow zum Hinzufügen von Screenshots

### 1. Screenshots erstellen
- Nimm Screenshots in hoher Qualität auf
- Achte auf gute Beleuchtung und Lesbarkeit
- Anonymisiere ggf. Benutzernamen in Test-Screenshots

### 2. Screenshots speichern
```bash
# Im Plugin-Verzeichnis
cd /Users/hans/Development/vzekc/vzekc-verlosung
# Screenshots nach docs/images kopieren
cp ~/Desktop/screenshot.png docs/images/01-verlosung-uebersicht-widget.png
```

### 3. In git committen
```bash
git add docs/images/*.png
git commit -m "Add screenshots for user documentation"
```

### 4. Zu Discourse hochladen (optional)
Wenn du die Dokumentation in Discourse veröffentlichen willst:
1. Öffne das BENUTZERHANDBUCH.md
2. Kopiere den Inhalt
3. Erstelle einen neuen Post in Discourse
4. Füge den Markdown-Text ein
5. Discourse zeigt Platzhalter für Bilder - drag & drop die Bilder aus docs/images/
6. Discourse lädt die Bilder automatisch hoch und ersetzt die Pfade

## Tipps für gute Screenshots

- **Auflösung**: Mindestens 1920x1080 für Desktop-Screenshots
- **Format**: PNG für UI-Screenshots (verlustfrei)
- **Fokus**: Zeige nur den relevanten Ausschnitt
- **Konsistenz**: Verwende immer die gleiche Browser-Größe/Zoom-Stufe
- **Markierungen**: Bei Bedarf rote Kreise/Pfeile für wichtige Elemente
