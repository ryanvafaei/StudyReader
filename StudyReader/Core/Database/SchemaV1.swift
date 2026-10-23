import Foundation
import GRDB

/// Migration `v1`: the full schema from ARCHITECTURE §4, FTS5 tables, and built-in categories.
/// Frozen once shipped. Later changes go into new named migrations.
enum SchemaV1 {
    static func create(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE category (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL UNIQUE COLLATE NOCASE,
              isBuiltin INTEGER NOT NULL DEFAULT 0,
              frequency TEXT NOT NULL DEFAULT 'normal' CHECK (frequency IN ('off','low','normal','high')),
              autoCreateCards INTEGER NOT NULL DEFAULT 1,
              sortOrder INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE document (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              categoryId TEXT NOT NULL REFERENCES category(id) ON DELETE RESTRICT,
              fileType TEXT NOT NULL CHECK (fileType IN ('pdf','markdown')),
              fileHash TEXT NOT NULL UNIQUE,
              originalFilename TEXT NOT NULL,
              originalBookmark BLOB,
              storedPath TEXT NOT NULL,
              pageCount INTEGER,
              coverPath TEXT,
              coverSource TEXT NOT NULL DEFAULT 'default' CHECK (coverSource IN ('default','custom','page')),
              extractionStatus TEXT NOT NULL DEFAULT 'pending' CHECK (extractionStatus IN ('pending','done','failed')),
              extractionVersion INTEGER NOT NULL DEFAULT 0,
              pdfPosition TEXT,
              textPosition INTEGER,
              progress REAL NOT NULL DEFAULT 0,
              addedAt REAL NOT NULL,
              lastOpenedAt REAL
            );

            CREATE TABLE documentText (
              documentId TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
              unitIndex INTEGER NOT NULL,
              startOffset INTEGER NOT NULL,
              text TEXT NOT NULL,
              runs TEXT,
              PRIMARY KEY (documentId, unitIndex)
            );

            CREATE TABLE highlight (
              id TEXT PRIMARY KEY,
              documentId TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
              kind TEXT NOT NULL CHECK (kind IN ('text','image')),
              view TEXT NOT NULL CHECK (view IN ('pdf','text','markdown')),
              color INTEGER NOT NULL DEFAULT 0 CHECK (color BETWEEN 0 AND 4),
              text TEXT NOT NULL DEFAULT '',
              richText TEXT NOT NULL DEFAULT '',
              editedText TEXT,
              note TEXT NOT NULL DEFAULT '',
              pageIndex INTEGER,
              positionKey REAL NOT NULL,
              anchor TEXT NOT NULL,
              anchorStatus TEXT NOT NULL DEFAULT 'ok' CHECK (anchorStatus IN ('ok','orphaned')),
              imagePath TEXT,
              createdAt REAL NOT NULL,
              updatedAt REAL NOT NULL
            );
            CREATE INDEX highlight_document ON highlight(documentId, positionKey);

            CREATE TABLE tag (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE, createdAt REAL NOT NULL);
            CREATE TABLE highlightTag (
              highlightId TEXT NOT NULL REFERENCES highlight(id) ON DELETE CASCADE,
              tagId TEXT NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
              PRIMARY KEY (highlightId, tagId));
            CREATE TABLE documentTag (
              documentId TEXT NOT NULL REFERENCES document(id) ON DELETE CASCADE,
              tagId TEXT NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
              PRIMARY KEY (documentId, tagId));
            CREATE INDEX highlightTag_tag ON highlightTag(tagId);

            CREATE TABLE documentNote (
              documentId TEXT PRIMARY KEY REFERENCES document(id) ON DELETE CASCADE,
              body TEXT NOT NULL DEFAULT '',
              updatedAt REAL NOT NULL);

            CREATE TABLE reviewCard (
              id TEXT PRIMARY KEY,
              highlightId TEXT NOT NULL REFERENCES highlight(id) ON DELETE CASCADE,
              cardType TEXT NOT NULL CHECK (cardType IN ('passive','cloze','qa')),
              clozeRanges TEXT,
              question TEXT,
              answer TEXT,
              fsrsCard TEXT NOT NULL,
              dueAt REAL NOT NULL,
              state TEXT NOT NULL,
              frequencyOverride TEXT CHECK (frequencyOverride IN ('off','low','normal','high')),
              suspended INTEGER NOT NULL DEFAULT 0,
              suspendedReason TEXT CHECK (suspendedReason IN ('mastery','frequencyOff','user')),
              introducedAt REAL,
              createdAt REAL NOT NULL);
            CREATE INDEX reviewCard_due ON reviewCard(dueAt) WHERE suspended = 0;
            CREATE INDEX reviewCard_highlight ON reviewCard(highlightId);

            CREATE TABLE themedReview (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              filter TEXT NOT NULL,
              cardsPerSession INTEGER NOT NULL DEFAULT 20,
              interval TEXT NOT NULL,
              orderMode TEXT NOT NULL DEFAULT 'dueFirst' CHECK (orderMode IN ('dueFirst','random')),
              lastCompletedAt REAL,
              createdAt REAL NOT NULL);

            CREATE TABLE reviewLog (
              id TEXT PRIMARY KEY,
              cardId TEXT NOT NULL REFERENCES reviewCard(id) ON DELETE CASCADE,
              rating INTEGER NOT NULL,
              reviewedAt REAL NOT NULL,
              sessionKind TEXT NOT NULL CHECK (sessionKind IN ('daily','themed')),
              themedReviewId TEXT REFERENCES themedReview(id) ON DELETE SET NULL,
              fsrsLog TEXT NOT NULL);

            CREATE TABLE exportTarget (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              scope TEXT NOT NULL,
              options TEXT NOT NULL,
              googleFileId TEXT,
              googleFolderId TEXT,
              format TEXT NOT NULL DEFAULT 'markdown' CHECK (format IN ('markdown','html')),
              keepInSync INTEGER NOT NULL DEFAULT 0,
              lastExportedAt REAL,
              lastStatus TEXT NOT NULL DEFAULT 'never',
              lastError TEXT,
              createdAt REAL NOT NULL);

            CREATE TABLE highlightEmbedding (
              highlightId TEXT PRIMARY KEY REFERENCES highlight(id) ON DELETE CASCADE,
              modelId TEXT NOT NULL,
              dimension INTEGER NOT NULL,
              vector BLOB NOT NULL,
              sourceHash TEXT NOT NULL);
            """)

        try db.create(virtualTable: "documentText_fts", using: FTS5()) { t in
            t.synchronize(withTable: "documentText")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("text")
        }

        try db.create(virtualTable: "highlight_fts", using: FTS5()) { t in
            t.synchronize(withTable: "highlight")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("text")
            t.column("editedText")
            t.column("note")
        }

        try db.create(virtualTable: "documentNote_fts", using: FTS5()) { t in
            t.synchronize(withTable: "documentNote")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("body")
        }

        try db.create(virtualTable: "document_fts", using: FTS5()) { t in
            t.synchronize(withTable: "document")
            t.tokenizer = .unicode61(diacritics: .remove)
            t.column("title")
            t.column("author")
        }

        for category in BuiltinCategory.allCases {
            try db.execute(
                sql: """
                    INSERT INTO category (id, name, isBuiltin, frequency, autoCreateCards, sortOrder)
                    VALUES (?, ?, 1, ?, 1, ?)
                    """,
                arguments: [category.id, category.name, category.frequency.rawValue, category.sortOrder]
            )
        }
    }
}
