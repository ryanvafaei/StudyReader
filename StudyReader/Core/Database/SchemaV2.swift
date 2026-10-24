import Foundation
import GRDB

/// Migration `v2` (ADR-0013): FK child indexes, `studyreader` FTS5 tables (ADR-0014),
/// and hand-written FTS sync triggers whose update triggers fire only for indexed columns.
/// Frozen once committed. Later changes go into new named migrations.
enum SchemaV2 {
    static func migrate(_ db: Database) throws { try db.execute(sql: sql) }

    static let sql: String = """
        -- 1. FK child indexes (M2)
        CREATE INDEX document_category ON document(categoryId);
        CREATE INDEX documentTag_tag ON documentTag(tagId);
        CREATE INDEX reviewLog_card ON reviewLog(cardId, reviewedAt);
        CREATE INDEX reviewLog_themedReview ON reviewLog(themedReviewId);

        -- 2. Drop GRDB synchronize(withTable:) triggers and v1 FTS tables
        DROP TRIGGER "__documentText_fts_ai";
        DROP TRIGGER "__documentText_fts_ad";
        DROP TRIGGER "__documentText_fts_au";
        DROP TRIGGER "__highlight_fts_ai";
        DROP TRIGGER "__highlight_fts_ad";
        DROP TRIGGER "__highlight_fts_au";
        DROP TRIGGER "__documentNote_fts_ai";
        DROP TRIGGER "__documentNote_fts_ad";
        DROP TRIGGER "__documentNote_fts_au";
        DROP TRIGGER "__document_fts_ai";
        DROP TRIGGER "__document_fts_ad";
        DROP TRIGGER "__document_fts_au";
        DROP TABLE documentText_fts;
        DROP TABLE highlight_fts;
        DROP TABLE documentNote_fts;
        DROP TABLE document_fts;

        -- 3. FTS tables with the studyreader tokenizer (ADR-0014)
        CREATE VIRTUAL TABLE documentText_fts USING fts5(text, content='documentText', tokenize='studyreader');
        CREATE VIRTUAL TABLE highlight_fts USING fts5(text, editedText, note, content='highlight', tokenize='studyreader');
        CREATE VIRTUAL TABLE documentNote_fts USING fts5(body, content='documentNote', tokenize='studyreader');
        CREATE VIRTUAL TABLE document_fts USING fts5(title, author, content='document', tokenize='studyreader');

        -- 4. Sync triggers; updates re-index only when an indexed column changes (L5)
        CREATE TRIGGER documentText_fts_ai AFTER INSERT ON documentText BEGIN
          INSERT INTO documentText_fts(rowid, text) VALUES (new.rowid, new.text);
        END;
        CREATE TRIGGER documentText_fts_ad AFTER DELETE ON documentText BEGIN
          INSERT INTO documentText_fts(documentText_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
        END;
        CREATE TRIGGER documentText_fts_au AFTER UPDATE OF text ON documentText BEGIN
          INSERT INTO documentText_fts(documentText_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
          INSERT INTO documentText_fts(rowid, text) VALUES (new.rowid, new.text);
        END;

        CREATE TRIGGER highlight_fts_ai AFTER INSERT ON highlight BEGIN
          INSERT INTO highlight_fts(rowid, text, editedText, note) VALUES (new.rowid, new.text, new.editedText, new.note);
        END;
        CREATE TRIGGER highlight_fts_ad AFTER DELETE ON highlight BEGIN
          INSERT INTO highlight_fts(highlight_fts, rowid, text, editedText, note) VALUES ('delete', old.rowid, old.text, old.editedText, old.note);
        END;
        CREATE TRIGGER highlight_fts_au AFTER UPDATE OF text, editedText, note ON highlight BEGIN
          INSERT INTO highlight_fts(highlight_fts, rowid, text, editedText, note) VALUES ('delete', old.rowid, old.text, old.editedText, old.note);
          INSERT INTO highlight_fts(rowid, text, editedText, note) VALUES (new.rowid, new.text, new.editedText, new.note);
        END;

        CREATE TRIGGER documentNote_fts_ai AFTER INSERT ON documentNote BEGIN
          INSERT INTO documentNote_fts(rowid, body) VALUES (new.rowid, new.body);
        END;
        CREATE TRIGGER documentNote_fts_ad AFTER DELETE ON documentNote BEGIN
          INSERT INTO documentNote_fts(documentNote_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
        END;
        CREATE TRIGGER documentNote_fts_au AFTER UPDATE OF body ON documentNote BEGIN
          INSERT INTO documentNote_fts(documentNote_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
          INSERT INTO documentNote_fts(rowid, body) VALUES (new.rowid, new.body);
        END;

        CREATE TRIGGER document_fts_ai AFTER INSERT ON document BEGIN
          INSERT INTO document_fts(rowid, title, author) VALUES (new.rowid, new.title, new.author);
        END;
        CREATE TRIGGER document_fts_ad AFTER DELETE ON document BEGIN
          INSERT INTO document_fts(document_fts, rowid, title, author) VALUES ('delete', old.rowid, old.title, old.author);
        END;
        CREATE TRIGGER document_fts_au AFTER UPDATE OF title, author ON document BEGIN
          INSERT INTO document_fts(document_fts, rowid, title, author) VALUES ('delete', old.rowid, old.title, old.author);
          INSERT INTO document_fts(rowid, title, author) VALUES (new.rowid, new.title, new.author);
        END;

        -- 5. Index existing rows
        INSERT INTO documentText_fts(documentText_fts) VALUES ('rebuild');
        INSERT INTO highlight_fts(highlight_fts) VALUES ('rebuild');
        INSERT INTO documentNote_fts(documentNote_fts) VALUES ('rebuild');
        INSERT INTO document_fts(document_fts) VALUES ('rebuild');
        """
}
