import XCTest
@testable import ArtemisIIWindow

final class MapProjectionTests: XCTestCase {
    func testRightEdgeNameStaysInsideThePlate() throws {
        let bounds = MapProjection.LabelBounds(x: 3, y: 3, width: 364, height: 142)
        let anchor = MapProjection.LabelAnchor(
            name: "Aristarchus Plateau",
            x: 306,
            y: 31,
            width: 106,
            height: 12
        )
        let box = try XCTUnwrap(MapProjection.placeLabels([anchor], in: bounds).first)
        XCTAssertEqual(box.width, 106, accuracy: 0.01)
        XCTAssertEqual(box.height, 12, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(box.x, bounds.x)
        XCTAssertGreaterThanOrEqual(box.y, bounds.y)
        XCTAssertLessThanOrEqual(box.maxX, bounds.maxX)
        XCTAssertLessThanOrEqual(box.maxY, bounds.maxY)
        XCTAssertLessThan(box.x + 7, anchor.x)
    }

    func testGeographicNamesFitPortraitAndLandscapePlates() throws {
        let names: [(String, Double, Double)] = [
            ("Glushko Crater", 8.11, 282.33),
            ("Ohm Crater", 18.32, 246.22),
            ("Aristarchus Plateau", 26.05, 309.26),
            ("Reiner Gamma", 7.2, 301.64),
            ("Orientale Basin", -19.37, 265.33),
            ("Vavilov Crater", -0.87, 221.23),
        ]
        let plates: [(Double, Double)] = [
            (370, 148),
            (120, 76),
            (112, 64),
        ]
        for plate in plates {
            let inset = 3.0
            let bounds = MapProjection.LabelBounds(
                x: inset,
                y: inset,
                width: plate.0 - inset * 2,
                height: plate.1 - inset * 2
            )
            var anchors: [MapProjection.LabelAnchor] = []
            for (name, lat, lon) in names {
                let raw = try XCTUnwrap(
                    MapProjection.point(
                        lon: lon,
                        lat: lat,
                        width: plate.0,
                        height: max(1, plate.1 - 8)
                    )
                )
                anchors.append(
                    MapProjection.LabelAnchor(
                        name: name,
                        x: raw.x,
                        y: raw.y,
                        width: Double(name.count) * 5.6,
                        height: 12
                    )
                )
            }
            let boxes = MapProjection.fitLabels(anchors, in: bounds)
            XCTAssertEqual(Set(boxes.map(\.name)), Set(names.map(\.0)), "plate \(plate)")
            for box in boxes {
                XCTAssertGreaterThanOrEqual(box.x, bounds.x - 0.01, box.name)
                XCTAssertGreaterThanOrEqual(box.y, bounds.y - 0.01, box.name)
                XCTAssertLessThanOrEqual(box.maxX, bounds.maxX + 0.01, box.name)
                XCTAssertLessThanOrEqual(box.maxY, bounds.maxY + 0.01, box.name)
            }
            for index in boxes.indices {
                for other in boxes.indices where other > index {
                    XCTAssertFalse(
                        boxes[index].x < boxes[other].maxX
                            && boxes[index].maxX > boxes[other].x
                            && boxes[index].y < boxes[other].maxY
                            && boxes[index].maxY > boxes[other].y,
                        "\(boxes[index].name) intersects \(boxes[other].name) on \(plate)"
                    )
                }
            }
            if plate.0 == 370 {
                let plateau = try XCTUnwrap(boxes.first { $0.name == "Aristarchus Plateau" })
                XCTAssertEqual(plateau.width, Double("Aristarchus Plateau".count) * 5.6, accuracy: 0.01)
            }
        }
    }
}
