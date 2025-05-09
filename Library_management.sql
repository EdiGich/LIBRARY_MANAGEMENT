-- Create the library_management database if it doesn't exist
CREATE DATABASE IF NOT EXISTS library_management;
USE library_management;

-- Drop existing tables to ensure a clean setup
DROP TABLE IF EXISTS Fines, Reservations, BorrowRecords, BookAuthors, Books, Categories, Authors, Users;

-- Table to store library members
CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    membership_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table to store book authors
CREATE TABLE Authors (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    bio TEXT
);

-- Table to store book categories
CREATE TABLE Categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

-- Table to store books
CREATE TABLE Books (
    book_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    category_id INT,
    isbn VARCHAR(20) UNIQUE,
    published_year INT,
    copies_available INT DEFAULT 1,
    FOREIGN KEY (category_id) REFERENCES Categories(category_id) ON DELETE SET NULL
);

-- Junction table for many-to-many relationship between Books and Authors
CREATE TABLE BookAuthors (
    book_id INT,
    author_id INT,
    PRIMARY KEY (book_id, author_id),
    FOREIGN KEY (book_id) REFERENCES Books(book_id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES Authors(author_id) ON DELETE CASCADE
);

-- Table to store borrowing records
CREATE TABLE BorrowRecords (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    book_id INT,
    borrow_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    return_date DATE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (book_id) REFERENCES Books(book_id) ON DELETE CASCADE
);

-- Table to store fines for late returns
CREATE TABLE Fines (
    fine_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    amount DECIMAL(10,2) NOT NULL,
    issue_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    paid BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- Table to store book reservations
CREATE TABLE Reservations (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    book_id INT,
    reservation_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (book_id) REFERENCES Books(book_id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX idx_email ON Users(email);
CREATE INDEX idx_isbn ON Books(isbn);
CREATE INDEX idx_borrow_user ON BorrowRecords(user_id);
CREATE INDEX idx_borrow_book ON BorrowRecords(book_id);

-- Trigger: Decrease copies_available when a book is borrowed
DELIMITER //
CREATE TRIGGER after_borrow_insert
AFTER INSERT ON BorrowRecords
FOR EACH ROW
BEGIN
    UPDATE Books
    SET copies_available = copies_available - 1
    WHERE book_id = NEW.book_id;
END //
DELIMITER ;

-- Trigger: Increase copies_available when a book is returned
DELIMITER //
CREATE TRIGGER after_return_update
AFTER UPDATE ON BorrowRecords
FOR EACH ROW
BEGIN
    IF NEW.return_date IS NOT NULL AND OLD.return_date IS NULL THEN
        UPDATE Books
        SET copies_available = copies_available + 1
        WHERE book_id = NEW.book_id;
    END IF;
END //
DELIMITER ;

-- Trigger: Add fine for overdue books (assuming 14-day loan period)
DELIMITER //
CREATE TRIGGER after_borrow_overdue
AFTER UPDATE ON BorrowRecords
FOR EACH ROW
BEGIN
    IF NEW.return_date IS NULL AND DATEDIFF(CURDATE(), NEW.borrow_date) > 14 THEN
        INSERT INTO Fines (user_id, amount, issue_date)
        VALUES (NEW.user_id, 5.00, CURDATE());
    END IF;
END //
DELIMITER ;

-- Stored Procedure: Borrow a book
DELIMITER //
CREATE PROCEDURE BorrowBook(IN userId INT, IN bookId INT)
BEGIN
    DECLARE available INT;
    SELECT copies_available INTO available FROM Books WHERE book_id = bookId;
    IF available > 0 THEN
        INSERT INTO BorrowRecords (user_id, book_id, borrow_date)
        VALUES (userId, bookId, CURRENT_TIMESTAMP);
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Book is not available';
    END IF;
END //
DELIMITER ;

-- Stored Procedure: Return a book
DELIMITER //
CREATE PROCEDURE ReturnBook(IN recordId INT)
BEGIN
    UPDATE BorrowRecords
    SET return_date = CURRENT_DATE
    WHERE record_id = recordId AND return_date IS NULL;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid record or book already returned';
    END IF;
END //
DELIMITER ;

-- Stored Procedure: Reserve a book
DELIMITER //
CREATE PROCEDURE ReserveBook(IN userId INT, IN bookId INT)
BEGIN
    INSERT INTO Reservations (user_id, book_id, reservation_date)
    VALUES (userId, bookId, CURRENT_DATE);
END //
DELIMITER ;

-- View: Active borrows
CREATE VIEW ActiveBorrows AS
SELECT u.full_name, b.title, br.borrow_date
FROM BorrowRecords br
JOIN Users u ON br.user_id = u.user_id
JOIN Books b ON br.book_id = b.book_id
WHERE br.return_date IS NULL;

-- View: Overdue books (more than 14 days)
CREATE VIEW OverdueBooks AS
SELECT u.full_name, b.title, br.borrow_date, DATEDIFF(CURDATE(), br.borrow_date) AS days_overdue
FROM BorrowRecords br
JOIN Users u ON br.user_id = u.user_id
JOIN Books b ON br.book_id = b.book_id
WHERE br.return_date IS NULL
AND br.borrow_date < DATE_SUB(CURDATE(), INTERVAL 14 DAY);

-- View: User fines
CREATE VIEW UserFines AS
SELECT u.full_name, SUM(f.amount) AS total_fines, COUNT(f.fine_id) AS fine_count
FROM Fines f
JOIN Users u ON f.user_id = u.user_id
WHERE f.paid = FALSE
GROUP BY u.user_id, u.full_name;

-- Sample Data
INSERT INTO Users (full_name, email, phone) VALUES
    ('John Doe', 'john.doe@example.com', '123-456-7890'),
    ('Jane Smith', 'jane.smith@example.com', '987-654-3210');

INSERT INTO Authors (name, bio) VALUES
    ('J.K. Rowling', 'British author, best known for Harry Potter series'),
    ('George Orwell', 'English novelist, known for 1984 and Animal Farm');

INSERT INTO Categories (name) VALUES
    ('Fantasy'),
    ('Dystopian');

INSERT INTO Books (title, category_id, isbn, published_year, copies_available) VALUES
    ('Harry Potter and the Sorcerer''s Stone', 1, '978-0439708180', 1997, 5),
    ('1984', 2, '978-0451524935', 1949, 3);

INSERT INTO BookAuthors (book_id, author_id) VALUES
    (1, 1),
    (2, 2);

INSERT INTO BorrowRecords (user_id, book_id, borrow_date) VALUES
    (1, 1, '2025-05-01'),
    (2, 2, '2025-04-20');

INSERT INTO Fines (user_id, amount, issue_date, paid) VALUES
    (2, 5.00, '2025-05-08', FALSE);

INSERT INTO Reservations (user_id, book_id, reservation_date) VALUES
    (1, 2, '2025-05-09');