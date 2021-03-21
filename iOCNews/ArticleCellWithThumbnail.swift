//
//  ArticleCellWithThumbnail.swift
//  iOCNews
//
//  Created by Peter Hedlund on 9/3/18.
//  Copyright © 2018 Peter Hedlund. All rights reserved.
//

import UIKit
import Kingfisher

class ArticleCellWithThumbnail: BaseArticleCell {
    @IBOutlet var mainSubView: UIView!
    @IBOutlet var contentContainerView: UIView!
    @IBOutlet var articleImage: UIImageView!
    @IBOutlet var favIconImage: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var dateLabel: UILabel!
    @IBOutlet var summaryLabel: UILabel!
    @IBOutlet var starContainerView: UIView!
    @IBOutlet var starImage: UIImageView!

    @IBOutlet var contentContainerLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var articleImageHeightConstraint: NSLayoutConstraint!
    @IBOutlet var articleImageWidthContraint: NSLayoutConstraint!
    @IBOutlet var titleLabelLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var summaryLabelLeadingConstraint: NSLayoutConstraint!
    @IBOutlet var mainSubviewHeightConstraint: NSLayoutConstraint!
    @IBOutlet var articleImageCenterYConstraint: NSLayoutConstraint!
    @IBOutlet var dateAuthorStackViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet var summarLabelVerticalSpacingConstraint: NSLayoutConstraint!

    override func configureView() {
        super.configureView()
        guard let item = self.item else {
            return
        }
        let isCompactView = UserDefaults.standard.bool(forKey: "CompactView")
        if isCompactView {
            summaryLabel.isHidden = true
            summaryLabel.text = nil
            summaryLabelLeadingConstraint.constant = 0
            summarLabelVerticalSpacingConstraint.isActive = false
        } else {
            summaryLabel.isHidden = false
            summaryLabel.font = item.summaryFont
            summaryLabel.text = item.summaryText
            summaryLabel.setThemeTextColor(item.summaryColor)
            summaryLabel.highlightedTextColor = self.summaryLabel.textColor
            summarLabelVerticalSpacingConstraint.isActive = true
        }
        titleLabel.font = item.titleFont
        dateLabel.font = item.dateFont
                
        titleLabel.text = item.title
        dateLabel.text = item.dateText
        
        titleLabel.setThemeTextColor(item.titleColor)
        dateLabel.setThemeTextColor(item.dateColor)
        
        titleLabel.highlightedTextColor = self.titleLabel.textColor;
        dateLabel.highlightedTextColor = self.dateLabel.textColor;

        if item.isFavIconHidden {
            favIconImage.isHidden = true
        } else {
            favIconImage.image = item.favIcon
            favIconImage.isHidden = false
            favIconImage.alpha = item.imageAlpha
        }

        if item.isThumbnailHidden || item.imageLink == nil {
            articleImage.isHidden = true
            contentContainerLeadingConstraint.constant = 0
            articleImageWidthContraint.constant = 0
            summaryLabelLeadingConstraint.constant = 0
        } else {
            articleImage.isHidden = false
            contentContainerLeadingConstraint.constant = 10
            if UIScreen.main.traitCollection.horizontalSizeClass == .compact {
                articleImageWidthContraint.constant = 66
                articleImageCenterYConstraint.constant = isCompactView ? 0 : -37
                summaryLabelLeadingConstraint.constant = -74
            } else {
                articleImageHeightConstraint.constant = isCompactView ? 66 : 112
                articleImageWidthContraint.constant = isCompactView ? 66 : 112
                articleImageCenterYConstraint.constant = 0
                summaryLabelLeadingConstraint.constant = 5
            }
            if (item.thumbnail != nil) {
                articleImage.image = item.thumbnail
            } else {
                if let link = item.imageLink, let url = URL(string: link) {
                    articleImage.kf.setImage(with: url)
                }
            }
        }

        articleImage.alpha = item.imageAlpha
        starImage.image = item.starIcon

        isHighlighted = false
    }

}
