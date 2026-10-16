//
//  SQLKeywords.swift
//  TablePro
//
//  Static catalogue of SQL keywords, functions, and operators
//

import Foundation

/// Static catalogue of SQL language elements for autocomplete
enum SQLKeywords {
    // MARK: - Keywords

    static let keywordSet: Set<String> = Set(keywords.filter { !$0.contains(" ") }.map { $0.lowercased() })

    /// Primary SQL keywords
    static let keywords: [String] = [
        // DQL
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "AS",
        "DISTINCT", "ALL", "TOP",

        // Joins
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
        "ON", "USING",

        // Ordering & Grouping
        "ORDER", "BY", "ASC", "DESC", "NULLS", "FIRST", "LAST",
        "GROUP", "HAVING",

        // Limiting
        "LIMIT", "OFFSET", "FETCH", "NEXT", "ROWS", "ONLY",

        // Set operations
        "UNION", "INTERSECT", "EXCEPT", "MINUS",

        // Subqueries
        "IN", "EXISTS", "ANY", "SOME",

        // DML
        "INSERT", "INTO", "VALUES", "DEFAULT",
        "UPDATE", "SET",
        "DELETE", "TRUNCATE",
        "MERGE", "UPSERT", "REPLACE", "CALL",

        // DDL
        "CREATE", "ALTER", "DROP", "RENAME", "MODIFY",
        "TABLE", "VIEW", "INDEX", "DATABASE", "SCHEMA",
        "PROCEDURE", "FUNCTION", "TRIGGER", "SEQUENCE",
        "COLUMN", "CONSTRAINT", "PRIMARY", "FOREIGN", "KEY",
        "REFERENCES", "UNIQUE", "CHECK",
        "AUTO_INCREMENT", "AUTOINCREMENT", "SERIAL",
        "ADD", "CHANGE", "AFTER", "COMMENT", "COLLATE", "CHARSET",
        "ENGINE", "TABLESPACE",

        // Index access methods, offered after USING in CREATE INDEX
        "BTREE", "HASH", "GIN", "GIST",

        // Data types (common)
        "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT",
        "DECIMAL", "NUMERIC", "FLOAT", "DOUBLE", "REAL",
        "VARCHAR", "CHAR", "TEXT", "BLOB", "CLOB",
        "DATE", "TIME", "DATETIME", "TIMESTAMP", "YEAR",
        "BOOLEAN", "BOOL", "BIT",
        "JSON", "JSONB", "XML",
        "UUID", "BINARY", "VARBINARY",

        // Conditionals
        "CASE", "WHEN", "THEN", "ELSE", "END",
        "IF", "IFNULL", "NULLIF", "COALESCE",

        // Comparison
        "BETWEEN", "LIKE", "ILIKE", "SIMILAR", "REGEXP", "RLIKE",
        "IS", "NULL", "TRUE", "FALSE", "UNKNOWN",

        // Transactions
        "BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "TRANSACTION",
        "ISOLATION", "LEVEL", "READ", "COMMITTED", "REPEATABLE", "SERIALIZABLE",

        // Window clause
        "OVER", "PARTITION", "UNBOUNDED", "PRECEDING", "FOLLOWING", "CURRENT ROW",
        "RANGE", "GROUPS",

        // PostgreSQL
        "RETURNING", "LATERAL", "CONCURRENTLY", "CONFLICT", "EXCLUDED",

        // MySQL
        "STRAIGHT_JOIN", "FORCE INDEX", "USE INDEX",
        "SIGNED", "UNSIGNED",

        // DCL
        "GRANT", "REVOKE", "PRIVILEGES", "USAGE",

        // Utility
        "DEALLOCATE", "PREPARE", "EXECUTE", "USE",

        // Other
        "WITH", "RECURSIVE", "TEMPORARY", "TEMP",
        "CASCADE", "RESTRICT", "NO", "ACTION",
        "EXPLAIN", "ANALYZE", "DESCRIBE", "SHOW"
    ]

    // MARK: - Functions

    /// Which database engines a function is available on.
    ///
    /// An option set rather than a single tag, because a function is often shared by a handful of
    /// engines rather than owned by one: `STRING_AGG` belongs to PostgreSQL *and* SQL Server,
    /// and rounding that to either would drop a suggestion the other engine accepts. `universal`
    /// carries every flag, so "runs everywhere" and "runs on these two" answer the same
    /// `includes(_:)` question.
    struct SQLFunctionDialect: OptionSet {
        let rawValue: Int

        static let mysql = SQLFunctionDialect(rawValue: 1 << 0)
        static let postgres = SQLFunctionDialect(rawValue: 1 << 1)
        static let mssql = SQLFunctionDialect(rawValue: 1 << 2)
        static let oracle = SQLFunctionDialect(rawValue: 1 << 3)
        static let sqlite = SQLFunctionDialect(rawValue: 1 << 4)

        static let universal: SQLFunctionDialect = [.mysql, .postgres, .mssql, .oracle, .sqlite]

        /// Every engine except SQL Server — the ANSI spellings SQL Server never adopted
        /// (`CURRENT_DATE`, `CURRENT_TIME`, …).
        static let standard: SQLFunctionDialect = [.mysql, .postgres, .oracle, .sqlite]

        /// Whether this function belongs on an engine tagged `engine`. An empty tag keeps the
        /// function everywhere, which is the safe direction for one whose engines aren't known.
        func includes(_ engine: SQLFunctionDialect) -> Bool {
            isEmpty || contains(engine)
        }
    }

    /// A catalogue entry: the spelling offered, the parameter skeleton inserted on accept, a
    /// description, and the engines that provide it.
    typealias SQLFunctionEntry = (
        name: String, signature: String, doc: String, dialect: SQLFunctionDialect
    )

    /// Aggregate functions
    static let aggregateFunctions: [SQLFunctionEntry] = [
        ("COUNT", "COUNT(;;expr)", "Count rows or non-null values", .universal),
        ("SUM", "SUM(;;expr)", "Sum of values", .universal),
        ("AVG", "AVG(;;expr)", "Average of values", .universal),
        ("MIN", "MIN(;;expr)", "Minimum value", .universal),
        ("MAX", "MAX(;;expr)", "Maximum value", .universal),
        ("GROUP_CONCAT", "GROUP_CONCAT(;;expr)", "Concatenate grouped values", [.mysql, .sqlite]),
        ("STRING_AGG", "STRING_AGG(;;expr, ;;sep)", "String aggregation", [.postgres, .mssql]),
        ("ARRAY_AGG", "ARRAY_AGG(;;expr)", "Aggregate into array", [.postgres]),
        ("STDDEV", "STDDEV(;;expr)", "Population standard deviation", [.mysql, .postgres, .oracle]),
        ("VARIANCE", "VARIANCE(;;expr)", "Population variance", [.mysql, .postgres, .oracle]),
        ("BIT_AND", "BIT_AND(;;expr)", "Bitwise AND aggregate", [.mysql]),
        ("BIT_OR", "BIT_OR(;;expr)", "Bitwise OR aggregate", [.mysql]),
        ("JSON_OBJECTAGG", "JSON_OBJECTAGG(;;key, ;;value)", "Aggregate into JSON object", [.mysql, .postgres]),
        ("JSON_ARRAYAGG", "JSON_ARRAYAGG(;;expr)", "Aggregate into JSON array", [.mysql, .postgres]),
    ]

    /// Date/Time functions
    static let dateTimeFunctions: [SQLFunctionEntry] = [
        ("NOW", "NOW()", "Current date and time", [.mysql, .postgres]),
        ("CURRENT_TIMESTAMP", "CURRENT_TIMESTAMP", "Current timestamp", .universal),
        ("CURRENT_DATE", "CURRENT_DATE", "Current date", .standard),
        ("CURRENT_TIME", "CURRENT_TIME", "Current time", .standard),
        ("CURDATE", "CURDATE()", "Current date (MySQL)", [.mysql]),
        ("CURTIME", "CURTIME()", "Current time (MySQL)", [.mysql]),
        ("SYSDATE", "SYSDATE()", "System date (MySQL)", [.mysql]),
        ("UTC_TIMESTAMP", "UTC_TIMESTAMP()", "Current UTC timestamp", [.mysql]),
        ("UTC_DATE", "UTC_DATE()", "Current UTC date", [.mysql]),
        ("UTC_TIME", "UTC_TIME()", "Current UTC time", [.mysql]),
        ("DATE", "DATE(;;expr)", "Extract date part", [.mysql, .sqlite]),
        ("TIME", "TIME(;;expr)", "Extract time part", [.mysql, .sqlite]),
        ("YEAR", "YEAR(;;date)", "Extract year", [.mysql, .mssql, .sqlite]),
        ("MONTH", "MONTH(;;date)", "Extract month", [.mysql, .mssql, .sqlite]),
        ("DAY", "DAY(;;date)", "Extract day", [.mysql, .mssql]),
        ("HOUR", "HOUR(;;time)", "Extract hour", [.mysql, .mssql]),
        ("MINUTE", "MINUTE(;;time)", "Extract minute", [.mysql, .mssql]),
        ("SECOND", "SECOND(;;time)", "Extract second", [.mysql, .mssql]),
        ("DAYOFWEEK", "DAYOFWEEK(;;date)", "Day of week (1=Sunday)", [.mysql]),
        ("DAYOFMONTH", "DAYOFMONTH(;;date)", "Day of month", [.mysql]),
        ("DAYOFYEAR", "DAYOFYEAR(;;date)", "Day of year", [.mysql]),
        ("WEEK", "WEEK(;;date)", "Week number", [.mysql]),
        ("QUARTER", "QUARTER(;;date)", "Quarter (1-4)", [.mysql]),
        ("DATE_ADD", "DATE_ADD(;;date, ;;interval)", "Add interval to date", [.mysql]),
        ("DATE_SUB", "DATE_SUB(;;date, ;;interval)", "Subtract interval from date", [.mysql]),
        ("DATEDIFF", "DATEDIFF(;;date1, ;;date2)", "Difference in days", [.mysql, .mssql]),
        ("TIMESTAMPDIFF", "TIMESTAMPDIFF(;;unit, ;;t1, ;;t2)", "Difference in specified unit", [.mysql]),
        ("DATE_FORMAT", "DATE_FORMAT(;;date, ;;format)", "Format date", [.mysql]),
        ("STR_TO_DATE", "STR_TO_DATE(;;str, ;;format)", "Parse string to date", [.mysql]),
        ("UNIX_TIMESTAMP", "UNIX_TIMESTAMP(;;date)", "Unix timestamp", [.mysql]),
        ("FROM_UNIXTIME", "FROM_UNIXTIME(;;ts)", "Date from Unix timestamp", [.mysql]),
        ("EXTRACT", "EXTRACT(;;field FROM ;;source)", "Extract date/time field", [.mysql, .postgres, .oracle]),
        ("DATE_TRUNC", "DATE_TRUNC(;;field, ;;source)", "Truncate to precision (PostgreSQL)", [.postgres]),
        ("AGE", "AGE(;;timestamp1, ;;timestamp2)", "Interval between timestamps (PostgreSQL)", [.postgres]),
        ("TO_TIMESTAMP", "TO_TIMESTAMP(;;str, ;;format)", "Parse string to timestamp", [.postgres, .oracle]),
        ("LAST_DAY", "LAST_DAY(;;date)", "Last day of month", [.mysql]),
        ("MAKEDATE", "MAKEDATE(;;year, ;;dayofyear)", "Create date from year and day", [.mysql]),
        ("MAKETIME", "MAKETIME(;;hour, ;;minute, ;;second)", "Create time value", [.mysql]),
    ]

    /// String functions
    static let stringFunctions: [SQLFunctionEntry] = [
        ("CONCAT", "CONCAT(;;str1, ;;str2, ...)", "Concatenate strings", .universal),
        ("CONCAT_WS", "CONCAT_WS(;;sep, ;;str1, ...)", "Concatenate with separator", [.mysql, .postgres, .mssql]),
        ("SUBSTRING", "SUBSTRING(;;str, ;;start, ;;len)", "Extract substring", .universal),
        ("SUBSTR", "SUBSTR(;;str, ;;start, ;;len)", "Extract substring", [.mysql, .postgres, .oracle, .sqlite]),
        ("LEFT", "LEFT(;;str, ;;len)", "Left part of string", [.mysql, .postgres, .mssql, .sqlite]),
        ("RIGHT", "RIGHT(;;str, ;;len)", "Right part of string", [.mysql, .postgres, .mssql, .sqlite]),
        ("LENGTH", "LENGTH(;;str)", "String length in bytes", [.mysql, .postgres, .sqlite]),
        ("CHAR_LENGTH", "CHAR_LENGTH(;;str)", "String length in characters", [.mysql, .postgres]),
        ("UPPER", "UPPER(;;str)", "Convert to uppercase", .universal),
        ("LOWER", "LOWER(;;str)", "Convert to lowercase", .universal),
        ("TRIM", "TRIM(;;str)", "Remove leading/trailing spaces", .universal),
        ("LTRIM", "LTRIM(;;str)", "Remove leading spaces", .universal),
        ("RTRIM", "RTRIM(;;str)", "Remove trailing spaces", .universal),
        ("REPLACE", "REPLACE(;;str, ;;from, ;;to)", "Replace occurrences", .universal),
        ("REVERSE", "REVERSE(;;str)", "Reverse string", [.mysql, .postgres, .mssql, .sqlite]),
        ("REPEAT", "REPEAT(;;str, ;;count)", "Repeat string", [.mysql, .postgres]),
        ("LPAD", "LPAD(;;str, ;;len, ;;pad)", "Left pad string", [.mysql, .postgres, .oracle]),
        ("RPAD", "RPAD(;;str, ;;len, ;;pad)", "Right pad string", [.mysql, .postgres, .oracle]),
        ("INSTR", "INSTR(;;str, ;;substr)", "Position of substring", [.mysql, .oracle, .sqlite]),
        ("LOCATE", "LOCATE(;;substr, ;;str)", "Position of substring", [.mysql]),
        ("POSITION", "POSITION(;;substr IN ;;str)", "Position of substring", [.mysql, .postgres]),
        ("FORMAT", "FORMAT(;;number, ;;decimals)", "Format number", [.mysql, .mssql]),
        ("SPACE", "SPACE(;;n)", "Return n spaces", [.mysql, .mssql, .oracle]),
        ("ASCII", "ASCII(;;str)", "ASCII code of first char", [.mysql, .postgres, .mssql, .oracle]),
        ("CHAR", "CHAR(;;n)", "Character from ASCII code", [.mysql, .postgres, .mssql, .oracle]),
        ("MD5", "MD5(;;str)", "MD5 hash", [.mysql, .postgres]),
        ("SHA1", "SHA1(;;str)", "SHA1 hash", [.mysql, .postgres]),
        ("SHA2", "SHA2(;;str, ;;bits)", "SHA2 hash", [.mysql]),
        ("REGEXP_REPLACE", "REGEXP_REPLACE(;;str, ;;pattern, ;;replacement)", "Replace using regex", [.mysql, .postgres, .oracle]),
        ("REGEXP_SUBSTR", "REGEXP_SUBSTR(;;str, ;;pattern)", "Extract regex match", [.mysql, .oracle]),
        ("SPLIT_PART", "SPLIT_PART(;;str, ;;delimiter, ;;n)", "Split and return nth part (PostgreSQL)", [.postgres]),
        ("INITCAP", "INITCAP(;;str)", "Capitalize first letter of each word", [.postgres, .oracle]),
        ("TRANSLATE", "TRANSLATE(;;str, ;;from, ;;to)", "Replace characters", [.postgres, .oracle, .sqlite]),
    ]

    /// Numeric functions
    static let numericFunctions: [SQLFunctionEntry] = [
        ("ABS", "ABS(;;n)", "Absolute value", .universal),
        ("ROUND", "ROUND(;;n, ;;decimals)", "Round to decimals", .universal),
        ("FLOOR", "FLOOR(;;n)", "Round down", .universal),
        ("CEIL", "CEIL(;;n)", "Round up", .universal),
        ("CEILING", "CEILING(;;n)", "Round up", .universal),
        ("TRUNCATE", "TRUNCATE(;;n, ;;decimals)", "Truncate to decimals", [.mysql, .postgres]),
        ("MOD", "MOD(;;n, ;;m)", "Modulo", [.mysql, .postgres, .oracle]),
        ("POW", "POW(;;x, ;;y)", "Power", [.mysql, .postgres, .mssql, .oracle]),
        ("POWER", "POWER(;;x, ;;y)", "Power", [.mysql, .postgres, .mssql, .oracle]),
        ("SQRT", "SQRT(;;n)", "Square root", .universal),
        ("EXP", "EXP(;;n)", "e^n", [.mysql, .postgres, .mssql, .oracle]),
        ("LOG", "LOG(;;n)", "Natural logarithm", .universal),
        ("LOG10", "LOG10(;;n)", "Base-10 logarithm", [.mysql, .postgres, .mssql]),
        ("LOG2", "LOG2(;;n)", "Base-2 logarithm", [.mysql, .postgres]),
        ("SIGN", "SIGN(;;n)", "Sign of number (-1, 0, 1)", [.mysql, .postgres, .mssql, .oracle]),
        ("RAND", "RAND()", "Random number 0-1", [.mysql, .mssql]),
        ("GREATEST", "GREATEST(;;v1, ;;v2, ...)", "Greatest value", [.mysql, .postgres, .oracle]),
        ("LEAST", "LEAST(;;v1, ;;v2, ...)", "Least value", [.mysql, .postgres, .oracle]),
        ("SIN", "SIN(;;n)", "Sine", [.mysql, .postgres, .mssql, .oracle]),
        ("COS", "COS(;;n)", "Cosine", [.mysql, .postgres, .mssql, .oracle]),
        ("TAN", "TAN(;;n)", "Tangent", [.mysql, .postgres, .mssql, .oracle]),
        ("ASIN", "ASIN(;;n)", "Arc sine", [.mysql, .postgres, .mssql, .oracle]),
        ("ACOS", "ACOS(;;n)", "Arc cosine", [.mysql, .postgres, .mssql, .oracle]),
        ("ATAN", "ATAN(;;n)", "Arc tangent", [.mysql, .postgres, .mssql, .oracle]),
        ("DEGREES", "DEGREES(;;n)", "Radians to degrees", [.mysql, .postgres, .mssql]),
        ("RADIANS", "RADIANS(;;n)", "Degrees to radians", [.mysql, .postgres, .mssql]),
        ("PI", "PI()", "Pi constant", [.mysql, .postgres, .mssql]),
    ]

    /// Null handling functions
    static let nullFunctions: [SQLFunctionEntry] = [
        ("COALESCE", "COALESCE(;;v1, ;;v2, ...)", "First non-null value", .universal),
        ("IFNULL", "IFNULL(;;expr, ;;alt)", "Return alt if expr is null", [.mysql, .sqlite]),
        ("NULLIF", "NULLIF(;;expr1, ;;expr2)", "Null if expr1 = expr2", .universal),
        ("NVL", "NVL(;;expr, ;;alt)", "Return alt if expr is null (Oracle)", [.oracle]),
        ("ISNULL", "ISNULL(;;expr)", "Check if null", [.mssql]),
    ]

    /// Type conversion functions
    static let conversionFunctions: [SQLFunctionEntry] = [
        ("CAST", "CAST(;;expr AS ;;type)", "Convert to type", .universal),
        ("CONVERT", "CONVERT(;;expr, ;;type)", "Convert to type", [.mysql, .mssql]),
        ("BINARY", "BINARY(;;str)", "Convert to binary string", [.mysql]),
    ]

    /// Window functions. The skeleton lands the caret inside `OVER` as well, because the two
    /// clauses that make a window function useful — `PARTITION BY` and `ORDER BY` — are empty in
    /// every window a user writes by hand, and leaving them out means typing them blind.
    static let windowFunctions: [SQLFunctionEntry] = [
        ("ROW_NUMBER", "ROW_NUMBER() OVER (PARTITION BY ;; ORDER BY ;; )", "Sequential row number", .universal),
        ("RANK", "RANK() OVER (PARTITION BY ;; ORDER BY ;; )", "Rank with gaps", .universal),
        ("DENSE_RANK", "DENSE_RANK() OVER (PARTITION BY ;; ORDER BY ;; )", "Rank without gaps", .universal),
        ("NTILE", "NTILE(;;n) OVER (PARTITION BY ;; ORDER BY ;; )", "Divide into n groups", .universal),
        ("LAG", "LAG(;;expr, ;;offset, ;;default) OVER (PARTITION BY ;; ORDER BY ;; )", "Previous row value", .universal),
        ("LEAD", "LEAD(;;expr, ;;offset, ;;default) OVER (PARTITION BY ;; ORDER BY ;; )", "Next row value", .universal),
        ("FIRST_VALUE", "FIRST_VALUE(;;expr) OVER (PARTITION BY ;; ORDER BY ;; )", "First value in partition", .universal),
        ("LAST_VALUE", "LAST_VALUE(;;expr) OVER (PARTITION BY ;; ORDER BY ;; )", "Last value in partition", .universal),
        ("NTH_VALUE", "NTH_VALUE(;;expr, ;;n) OVER (PARTITION BY ;; ORDER BY ;; )", "Nth value in partition", .universal),
        ("PERCENT_RANK", "PERCENT_RANK() OVER (PARTITION BY ;; ORDER BY ;; )", "Relative rank (0-1)", .universal),
        ("CUME_DIST", "CUME_DIST() OVER (PARTITION BY ;; ORDER BY ;; )", "Cumulative distribution", .universal),
    ]

    /// JSON functions
    static let jsonFunctions: [SQLFunctionEntry] = [
        ("JSON_EXTRACT", "JSON_EXTRACT(;;json, ;;path)", "Extract value from JSON", [.mysql]),
        ("JSON_OBJECT", "JSON_OBJECT(;;key, ;;value, ...)", "Create JSON object", [.mysql, .postgres]),
        ("JSON_ARRAY", "JSON_ARRAY(;;val1, ;;val2, ...)", "Create JSON array", [.mysql, .postgres]),
        ("JSON_KEYS", "JSON_KEYS(;;json)", "Get JSON object keys", [.mysql]),
        ("JSON_LENGTH", "JSON_LENGTH(;;json)", "Get JSON length", [.mysql]),
        ("JSON_TYPE", "JSON_TYPE(;;json)", "Get JSON value type", [.mysql]),
        ("JSON_VALID", "JSON_VALID(;;json)", "Check if valid JSON", [.mysql]),
        ("JSON_CONTAINS", "JSON_CONTAINS(;;json, ;;val)", "Check if JSON contains value", [.mysql]),
        ("JSON_SET", "JSON_SET(;;json, ;;path, ;;val)", "Set value in JSON", [.mysql]),
        ("JSON_INSERT", "JSON_INSERT(;;json, ;;path, ;;val)", "Insert into JSON", [.mysql]),
        ("JSON_REPLACE", "JSON_REPLACE(;;json, ;;path, ;;val)", "Replace in JSON", [.mysql]),
        ("JSON_REMOVE", "JSON_REMOVE(;;json, ;;path)", "Remove from JSON", [.mysql]),
        ("JSON_UNQUOTE", "JSON_UNQUOTE(;;json)", "Unquote JSON string", [.mysql]),
        ("JSON_BUILD_OBJECT", "JSON_BUILD_OBJECT(;;key, ;;value, ...)", "Build JSON object (PostgreSQL)", [.postgres]),
        ("JSON_BUILD_ARRAY", "JSON_BUILD_ARRAY(;;val1, ;;val2, ...)", "Build JSON array (PostgreSQL)", [.postgres]),
        ("JSONB_SET", "JSONB_SET(;;target, ;;path, ;;new_value)", "Set value in JSONB (PostgreSQL)", [.postgres]),
        ("JSON_EACH", "JSON_EACH(;;json)", "Expand JSON to key-value pairs (PostgreSQL)", [.postgres]),
        ("ROW_TO_JSON", "ROW_TO_JSON(;;record)", "Convert row to JSON (PostgreSQL)", [.postgres]),
        ("JSON_AGG", "JSON_AGG(;;expr)", "Aggregate to JSON array (PostgreSQL)", [.postgres]),
        ("JSONB_AGG", "JSONB_AGG(;;expr)", "Aggregate to JSONB array (PostgreSQL)", [.postgres]),
    ]

    /// All functions combined
    static var allFunctions: [SQLFunctionEntry] {
        aggregateFunctions + dateTimeFunctions + stringFunctions +
            numericFunctions + nullFunctions + conversionFunctions +
            windowFunctions + jsonFunctions
    }

    // MARK: - Operators

    /// Comparison operators
    static let operators: [(symbol: String, doc: String)] = [
        ("=", "Equal to"),
        ("<>", "Not equal to"),
        ("!=", "Not equal to"),
        ("<", "Less than"),
        (">", "Greater than"),
        ("<=", "Less than or equal"),
        (">=", "Greater than or equal"),
        ("<=>", "Null-safe equal (MySQL)"),
    ]

    // MARK: - Completion Items

    /// Get all keyword completion items
    static func keywordItems() -> [SQLCompletionItem] {
        keywords.map { SQLCompletionItem.keyword($0) }
    }

    /// Function completion items for one engine. `engine` is the flag of whatever the editor is
    /// connected to; `nil` keeps the whole catalogue, which is the right answer for a connection
    /// whose type hasn't resolved yet and for engines the tag table doesn't model.
    static func functionItems(for engine: SQLFunctionDialect?) -> [SQLCompletionItem] {
        allFunctions
            .filter { entry in
                guard let engine else { return true }
                return entry.dialect.includes(engine)
            }
            .map { fn in
                SQLCompletionItem.function(fn.name, signature: fn.signature, documentation: fn.doc)
            }
    }

    /// Get all operator completion items
    static func operatorItems() -> [SQLCompletionItem] {
        operators.map { op in
            SQLCompletionItem.operator(op.symbol, documentation: op.doc)
        }
    }
}
