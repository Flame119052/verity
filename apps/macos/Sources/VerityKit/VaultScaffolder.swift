import Foundation

public enum VaultScaffolderError: Error, LocalizedError, Sendable {
    case destinationExists(String)
    case incompleteCreation(String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let path): "A file or folder already exists at \(path). Choose a new location."
        case .incompleteCreation(let message): "The new vault could not be created: \(message)"
        }
    }
}

public struct VaultScaffolder: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func create(at destination: URL, date: Date = Date()) throws {
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw VaultScaffolderError.destinationExists(destination.path)
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).verity-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging.appendingPathComponent("Progress"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: staging.appendingPathComponent("Boards"), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: staging.appendingPathComponent("Courses"), withIntermediateDirectories: true)
            let today = Self.dateFormatter.string(from: date)
            for (path, contents) in Self.templates(today: today) {
                let url = staging.appendingPathComponent(path)
                try Data(contents.utf8).write(to: url, options: [.atomic])
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw VaultScaffolderError.incompleteCreation(error.localizedDescription)
        }
    }

    private static func templates(today: String) -> [(String, String)] {
        [
            ("Progress/Homework.md", """
            ---
            type: homework_tracker
            status: Active
            last_updated: \(today)
            ---

            # Homework Tracker

            Track daily homework and tasks.

            | id | subject | task | due_date | est_minutes | priority_tag | status | created_at |
            | --- | --- | --- | --- | --- | --- | --- | --- |
            """),
            ("Progress/Course-Cursor.md", """
            ---
            type: course_cursor
            status: Active
            mode: Course-first, no weekly schedule
            last_updated: \(today)
            ---

            # Course Cursor

            This file tracks active course progress. Updated by VERITY.

            | course | last_completed_topic | last_completed_blockType | date |
            | --- | --- | --- | --- |
            """),
            ("Progress/Time-Log.md", """
            ---
            type: time_log
            status: Active
            last_updated: \(today)
            ---

            # Time Log

            Append-only log of study and homework time.

            | date | ref_type | ref_label | course | topic | blockType | started_at | stopped_at | minutes |
            | --- | --- | --- | --- | --- | --- | --- | --- | --- |
            """),
            ("Boards/Syllabus-Checklist.md", """
            ---
            type: syllabus_checklist
            source: "fill in your board/curriculum's official syllabus"
            last_updated: \(today)
            status: Active
            ---

            # Syllabus Checklist

            ## Mathematics

            | Unit | Chapter | Marks Weight | Status | Evidence |
            | --- | --- | --- | --- | --- |

            ## Science

            | Unit | Chapter / Topic | Marks Weight | Status | Evidence |
            | --- | --- | --- | --- | --- |

            ## Social Science

            | Area | Chapter | Marks Weight | Status | Evidence |
            | --- | --- | --- | --- | --- |

            ## English Language and Literature

            | Area | Item | Marks Weight | Status | Evidence |
            | --- | --- | --- | --- | --- |

            ## Sanskrit / Hindi

            | Language | Area | Marks Weight | Status | Evidence |
            | --- | --- | --- | --- | --- |
            """),
            ("Courses/Boards-Daily-Block-Library.md", """
            ---
            name: "Boards Daily Block Library"
            type: "Board Prep"
            status: Active
            start: \(today)
            progress_pct: 0
            ---

            # Boards Daily Block Library

            ## Mathematics Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## Science Physics Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## Science Chemistry Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## Science Biology Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## SST History Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## SST Geography Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## SST Economics Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## SST Political Science Block Bank

            | Chapter | First Pass Block | Drill Block | Timed Benchmark |
            | --- | --- | --- | --- |

            ## English Block Bank

            | Area | Block | Output | Benchmark |
            | --- | --- | --- | --- |

            ## Hindi Block Bank

            | Area | Block | Output | Benchmark |
            | --- | --- | --- | --- |
            """),
            ("Courses/Competition-Daily-Block-Library.md", """
            ---
            name: "Competition Daily Block Library"
            type: "Exam Prep"
            status: Active
            start: \(today)
            progress_pct: 0
            ---

            # Competition Daily Block Library

            Add a `## <Name> Block Bank` section for each competition track.
            """)
        ]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
