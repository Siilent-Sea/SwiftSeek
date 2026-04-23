import Foundation

public enum Schema {
    public static let currentVersion: Int32 = 3

    public struct Migration {
        public let target: Int32
        public let statements: [String]
    }

    public static let migrations: [Migration] = [
        Migration(target: 1, statements: [
            """
            CREATE TABLE IF NOT EXISTS meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER,
                path TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                name_lower TEXT NOT NULL,
                is_dir INTEGER NOT NULL,
                size INTEGER NOT NULL DEFAULT 0,
                mtime INTEGER NOT NULL DEFAULT 0,
                inode INTEGER,
                volume_id INTEGER
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_files_name_lower ON files(name_lower);",
            "CREATE INDEX IF NOT EXISTS idx_files_parent ON files(parent_id);",
            """
            CREATE TABLE IF NOT EXISTS roots (
                id INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                enabled INTEGER NOT NULL DEFAULT 1
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS excludes (
                id INTEGER PRIMARY KEY,
                pattern TEXT NOT NULL UNIQUE
            );
            """
        ]),
        Migration(target: 2, statements: [
            "ALTER TABLE files ADD COLUMN path_lower TEXT NOT NULL DEFAULT '';",
            "UPDATE files SET path_lower = LOWER(path);",
            "CREATE INDEX IF NOT EXISTS idx_files_path_lower ON files(path_lower);",
            """
            CREATE TABLE IF NOT EXISTS file_grams (
                file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                gram TEXT NOT NULL,
                PRIMARY KEY(file_id, gram)
            ) WITHOUT ROWID;
            """,
            "CREATE INDEX IF NOT EXISTS idx_file_grams_gram ON file_grams(gram);"
        ]),
        Migration(target: 3, statements: [
            """
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        ])
    ]
}
